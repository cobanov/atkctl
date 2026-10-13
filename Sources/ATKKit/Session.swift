import Foundation

public enum ReportRate: Int, CaseIterable, Sendable {
    case hz125 = 125, hz250 = 250, hz500 = 500, hz1000 = 1000, hz2000 = 2000, hz4000 = 4000, hz8000 = 8000

    // Device encoding, from ATK Hub.
    private static let codes: [ReportRate: UInt8] = [
        .hz1000: 0, .hz500: 1, .hz250: 2, .hz125: 3, .hz8000: 4, .hz4000: 5, .hz2000: 6,
    ]

    public var code: UInt8 { Self.codes[self]! }
    public init?(code: UInt8) {
        guard let rate = Self.codes.first(where: { $0.value == code })?.key else { return nil }
        self = rate
    }
}

public enum ConnectionType: UInt8, Sendable {
    case receiver1K = 0, receiver4K = 1, wired1K = 2, wired8K = 3, receiver2K = 4, receiver8K = 5, wired2K = 6, wired4K = 7

    public var label: String {
        switch self {
        case .receiver1K: "receiver, 1K"
        case .receiver2K: "receiver, 2K"
        case .receiver4K: "receiver, 4K"
        case .receiver8K: "receiver, 8K"
        case .wired1K: "cable, 1K"
        case .wired2K: "cable, 2K"
        case .wired4K: "cable, 4K"
        case .wired8K: "cable, 8K"
        }
    }

    /// The fastest polling rate the link carries.
    public var maxReportRate: ReportRate {
        switch self {
        case .receiver1K, .wired1K: .hz1000
        case .receiver2K, .wired2K: .hz2000
        case .receiver4K, .wired4K: .hz4000
        case .receiver8K, .wired8K: .hz8000
        }
    }
}

/// The values the mouse reports for `getCurrentConfig`.
public struct MouseConfig: Equatable, Sendable {
    public let profile: Int
    public let reportRate: ReportRate?
    /// 1 to 11; ATK Hub shows it as 0.7 to 1.7 mm.
    public let liftOffLevel: Int
    public let motionSync: Bool
    public let angleSnapping: Bool
    public let rippleControl: Bool
    public let sleepSeconds: Int
    public let debounceMs: Int

    public init(_ r: Reply) {
        profile = Int(r.u8(0))
        reportRate = ReportRate(code: r.u8(2))
        // Bytes 3 and 4 are not what ATK Hub's names for them say (DPI, lift-off); it ignores them, and so do we.
        liftOffLevel = Int(r.u8(5)) + 1
        motionSync = r.u8(6) != 0
        angleSnapping = r.u8(7) != 0
        rippleControl = r.u8(8) != 0
        sleepSeconds = Int(r.u16(9))
        debounceMs = Int(r.u8(11))
    }

    public var liftOffMillimetres: Double { MouseConfig.millimetres(liftOffLevel) }

    static func millimetres(_ level: Int) -> Double { Double(6 + level) / 10 }
}

public struct DPIStage: Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let color: (r: UInt8, g: UInt8, b: UInt8)

    public static func == (a: DPIStage, b: DPIStage) -> Bool {
        a.x == b.x && a.y == b.y && a.color == b.color
    }
}

/// The DPI table kept at address 1 of the mouse's settings memory.
/// Byte 1 is the number of slots (8); the stages in use are the ones with a value.
public struct DPITable: Equatable, Sendable {
    public let activeIndex: Int
    public let stages: [DPIStage]

    public var active: DPIStage? { stages.indices.contains(activeIndex) ? stages[activeIndex] : nil }

    public init(_ bytes: [UInt8]) {
        activeIndex = Int(bytes[0])
        let slots = min(Int(bytes[1]), 8)
        stages = (0..<slots).map { i in
            let o = 2 + i * 8
            return DPIStage(
                x: Int(bytes[o]) | Int(bytes[o + 1]) << 8,
                y: Int(bytes[o + 2]) | Int(bytes[o + 3]) << 8,
                color: (r: bytes[o + 6], g: bytes[o + 5], b: bytes[o + 4]))
        }
        .prefix { $0.x > 0 }
        .map { $0 }
    }
}

public struct Battery: Sendable {
    public let percent: Int
    public let charging: Bool

    public init(percent: Int, charging: Bool) {
        self.percent = percent
        self.charging = charging
    }
}

public struct ReceiverStatus: Sendable {
    public let connected: Bool
    /// What `0x84` reports. It reads 0 while the mouse sleeps too, so it does not say whether
    /// the receiver remembers a mouse; ATK Hub only reads it while pairing.
    public let paired: Bool
}

/// A mouse and/or its receiver. Mouse commands go over the cable when there is one,
/// otherwise through the receiver, which forwards anything sent with target 1.
public final class Session {
    public let mouse: HIDChannel?
    public let receiver: HIDChannel?

    public convenience init(endpoints: [Endpoint] = Endpoint.discover()) {
        self.init(channels: endpoints.map(HIDChannel.init))
    }

    /// One channel per device: a second channel on the same device would see the first one's replies.
    public init(channels: [HIDChannel]) {
        mouse = channels.first { !$0.endpoint.isReceiver }
        receiver = channels.first { $0.endpoint.isReceiver }
    }

    public var isEmpty: Bool { mouse == nil && receiver == nil }

    /// Sends a command to whichever device answers it, routing mouse commands through the receiver if needed.
    public func send(_ command: Command, payload: [UInt8] = []) throws -> Reply {
        if command.isReceiverCommand {
            guard let channel = receiver ?? mouse else { throw ATKError.notConnected("no ATK / VXE device found") }
            return try channel.transfer(command, target: .device, payload: payload)
        }
        if let mouse { return try mouse.transfer(command, target: .device, payload: payload) }
        guard let receiver else { throw ATKError.notConnected("no ATK / VXE device found") }
        return try receiver.transfer(command, target: .mouseBehindReceiver, payload: payload)
    }

    // MARK: reading

    public func firmwareVersion() throws -> String {
        let r = try send(.getFirmwareVersion)
        return "\(r.u8(0)).\(r.u8(1)).\(r.u8(2))"
    }

    public func receiverVersion() throws -> String {
        guard receiver != nil else { throw ATKError.notConnected("no receiver plugged in") }
        let r = try send(.getReceiverVersion)
        return "\(r.u8(0)).\(r.u8(1)).\(r.u8(2))"
    }

    public func receiverStatus() throws -> ReceiverStatus {
        guard receiver != nil else { throw ATKError.notConnected("no receiver plugged in") }
        return ReceiverStatus(connected: try send(.getReceiverConnectStatus).u8(0) != 0,
                              paired: try send(.getPairStatus).u8(0) != 0)
    }

    /// Company and model ID of the mouse, which `Catalog.mouse(cid:mid:)` turns into a model.
    /// ATK Hub asks the receiver with 0x89 and the mouse itself with 0x4A; this tries both.
    public func mouseID() throws -> (cid: Int, mid: Int) {
        var lastError: Error = ATKError.noReply(.getMouseIDViaReceiver)
        for command in receiver != nil && mouse == nil ? [Command.getMouseIDViaReceiver, .getMouseID] : [.getMouseID] {
            do {
                let r = try send(command, payload: [0])
                return (Int(r.u8(1)), Int(r.u32(2)))
            } catch ATKError.secureInput {
                throw ATKError.secureInput
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// The connected mouse's product ID: its own over a cable, worked out from its ID otherwise.
    public func mouseProductID() -> Int? {
        if let mouse { return mouse.endpoint.productID }
        guard let id = try? mouseID() else { return nil }
        return Catalog.mouse(cid: id.cid, mid: id.mid)
    }

    public func connectionType() throws -> ConnectionType? {
        ConnectionType(rawValue: try send(.getDeviceType).u8(0))
    }

    public func battery() throws -> Battery {
        Battery(percent: Int(try send(.getBatteryLevel).u8(0)),
                charging: try send(.getChargingStatus).u8(0) == 1)
    }

    public func config() throws -> MouseConfig {
        MouseConfig(try send(.getCurrentConfig))
    }

    public func dpiTable() throws -> DPITable {
        var bytes: [UInt8] = []
        for chunk in 0..<7 {  // ATK Hub reads 7 blocks of 10 bytes from address 1
            let address = UInt16(1 + chunk * 10)
            let r = try send(.getAddressData, payload: [UInt8(address & 0xFF), UInt8(address >> 8), 10])
            bytes += r.payload(3..<13)
        }
        return DPITable(bytes)
    }

    // MARK: settings

    /// Values ATK Hub offers; the firmware takes seconds.
    public static let sleepChoices = [30, 60, 120, 180, 300, 1200, 1500, 1800]
    public static let debounceChoices = [0, 1, 2, 4, 8, 15, 20]

    public func setSleep(seconds: Int) throws {
        guard Self.sleepChoices.contains(seconds) else {
            throw ATKError.invalidValue("sleep must be one of 30s, 1m, 2m, 3m, 5m, 20m, 25m, 30m")
        }
        _ = try send(.setSleepTime, payload: [UInt8(seconds & 0xFF), UInt8(seconds >> 8)])
    }

    public func setReportRate(_ rate: ReportRate) throws {
        _ = try send(.setReportRate, payload: [rate.code])
    }

    public func setDebounce(ms: Int) throws {
        guard Self.debounceChoices.contains(ms) else {
            throw ATKError.invalidValue("debounce must be one of 0, 1, 2, 4, 8, 15, 20 ms")
        }
        _ = try send(.setDebounceTime, payload: [UInt8(ms)])
    }

    /// Lift-off distance in tenths of a millimetre steps, 0.7 to 1.7 mm, as ATK Hub's slider sets it.
    public func setLiftOff(millimetres: Double) throws {
        let level = Int((millimetres * 10).rounded()) - 6
        guard (1...11).contains(level) else { throw ATKError.invalidValue("lift-off must be 0.7 to 1.7 mm") }
        _ = try send(.setLiftOff, payload: [0, UInt8(level - 1)])
    }

    public func setMotionSync(_ on: Bool) throws { _ = try send(.setMotionSync, payload: [on ? 1 : 0]) }
    public func setRippleControl(_ on: Bool) throws { _ = try send(.setRippleControl, payload: [on ? 1 : 0]) }
    public func setAngleSnapping(_ on: Bool) throws { _ = try send(.setLinearCorrection, payload: [on ? 1 : 0]) }

    /// Changes one stage's value, keeping its colour; the active stage stays active, as in ATK Hub.
    public func setDPI(stage index: Int, to value: Int) throws {
        let table = try dpiTable()
        guard table.stages.indices.contains(index) else {
            throw ATKError.invalidValue("the mouse has \(table.stages.count) DPI stages")
        }
        guard (50...26000).contains(value), value % 50 == 0 else {
            throw ATKError.invalidValue("DPI must be a multiple of 50 between 50 and 26000")
        }
        let old = table.stages[index]
        try writeStage(index, DPIStage(x: value, y: value, color: old.color), active: index == table.activeIndex)
    }

    /// Makes another stage the active one, the way ATK Hub does: by rewriting that stage with its flag set.
    public func selectDPIStage(_ index: Int) throws {
        let table = try dpiTable()
        guard table.stages.indices.contains(index) else {
            throw ATKError.invalidValue("the mouse has \(table.stages.count) DPI stages")
        }
        try writeStage(index, table.stages[index], active: true)
    }

    private func writeStage(_ index: Int, _ stage: DPIStage, active: Bool) throws {
        let x = UInt16(stage.x), y = UInt16(stage.y), c = stage.color
        _ = try send(.setDPI, payload: [UInt8(index), UInt8(x & 0xFF), UInt8(x >> 8), UInt8(y & 0xFF), UInt8(y >> 8),
                                        c.b, c.g, c.r, 0, active ? 1 : 0])
    }

    // MARK: pairing

    /// Forgets the receiver's current mouse, then listens for a new one until `timeout`.
    public func pair(timeout: TimeInterval = 30, progress: (TimeInterval) -> Void = { _ in }) throws -> Bool {
        guard receiver != nil else { throw ATKError.notConnected("pairing needs the receiver plugged in") }
        _ = try send(.clearPairing)
        _ = try send(.startPairing)
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            progress(Date().timeIntervalSince(start))
            if try receiverStatus().connected { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }
}
