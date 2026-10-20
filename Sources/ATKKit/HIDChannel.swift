import Foundation
import IOKit.hid

/// The vendor HID interface: usage page 0xFF05 for BitMouse, 0xFF04 for supported Compx devices.
public struct Endpoint {
    public let device: IOHIDDevice
    public let productID: Int
    public let product: String
    public let manufacturer: String
    public let locationID: Int

    public var model: Catalog.Model? { Catalog.models[productID] }
    public var usesCompx: Bool { [0x1119, 0x111A].contains(productID) }
    public var isReceiver: Bool { model?.kind == .receiver }
    public var isTested: Bool { Catalog.tested.contains(productID) }

    // Kept so the devices it hands out stay valid. It is not scheduled on a run loop,
    // so it does not see devices plugged in later: pass `rescan` to look again.
    nonisolated(unsafe) private static var manager: IOHIDManager?

    private static func makeManager() -> IOHIDManager {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: Catalog.vendorID] as CFDictionary)
        // Without opening the manager, macOS refuses reports to devices that also expose a keyboard usage.
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        return manager
    }

    /// Every connected device that speaks the protocol, mice first.
    public static func discover(rescan: Bool = false) -> [Endpoint] {
        if rescan || manager == nil { manager = makeManager() }
        guard let manager, let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return devices.compactMap { device -> Endpoint? in
            let pairs = property(device, kIOHIDDeviceUsagePairsKey) as? [[String: Int]] ?? []
            let productID = property(device, kIOHIDProductIDKey) as? Int ?? 0
            let page = [0x1119, 0x111A].contains(productID) ? 0xFF04 : 0xFF05
            guard pairs.contains(where: { $0[kIOHIDDeviceUsagePageKey] == page }) else { return nil }
            return Endpoint(
                device: device,
                productID: property(device, kIOHIDProductIDKey) as? Int ?? 0,
                product: property(device, kIOHIDProductKey) as? String ?? "?",
                manufacturer: property(device, kIOHIDManufacturerKey) as? String ?? "?",
                locationID: property(device, kIOHIDLocationIDKey) as? Int ?? 0)
        }
        .sorted { ($0.isReceiver ? 1 : 0, $0.locationID) < ($1.isReceiver ? 1 : 0, $1.locationID) }
    }

    private static func property(_ device: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }
}

public enum ATKError: Error, CustomStringConvertible {
    case exclusiveAccess(product: String)
    case secureInput
    case inputMonitoring
    case openFailed(product: String, code: IOReturn)
    case sendFailed(Command, IOReturn)
    case noReply(Command)
    case deviceRejected(Command)
    case notConnected(String)
    case invalidValue(String)
    case unsupportedProtocolCommand(Command)

    public var description: String {
        switch self {
        case .exclusiveAccess(let p):
            return "\(p) is held exclusively by another process (often Karabiner-Elements); run `atkctl doctor`"
        case .secureInput:
            return "macOS is blocking keyboard-class devices because Secure Input is on (screen locked or a password field focused); unlock and try again"
        case .inputMonitoring:
            return "macOS denied access to the device: allow your terminal app under System Settings › Privacy & Security › Input Monitoring"
        case .openFailed(let p, let code): return "could not open \(p): IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16))"
        case .sendFailed(let c, let code): return "sending \(c) failed: IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16))"
        case .noReply(let c): return "no reply to \(c)"
        case .deviceRejected(let c): return "the device rejected \(c)"
        case .notConnected(let what): return what
        case .invalidValue(let what): return what
        case .unsupportedProtocolCommand(let c): return "\(c) is not yet supported for this Compx receiver; use ATK Hub for this operation"
        }
    }
}

/// Request/reply over output and input report 8, the way ATK Hub does it:
/// a reply belongs to the request whose command byte it echoes.
public final class HIDChannel {
    public let endpoint: Endpoint
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var replies: [Reply] = []
    private var compxReplies: [[UInt8]] = []
    private var pendingCompxCommand: UInt8?
    private var runLoop: CFRunLoop?
    /// Reports the device sends on its own, such as `DeviceEvent.dpiChanged` when its DPI button
    /// is pressed. Called on the channel's thread whenever that thread's run loop runs in its
    /// default mode, and while waiting for a reply.
    public var onEvent: ((DeviceEvent) -> Void)?

    /// Replies are only listened for in this mode, so waiting for one never runs anything else
    /// that is queued on the thread's run loop.
    static let replyMode = CFRunLoopMode("dev.cobanov.atkctl.reply" as CFString)

    public static let timeout: TimeInterval = 0.5
    public static let attempts = 3

    public init(_ endpoint: Endpoint) {
        self.endpoint = endpoint
    }

    deinit {
        close()
        buffer.deallocate()
    }

    /// Opens the device on the calling thread; use the channel from that thread only.
    public func open() throws {
        guard runLoop == nil else { return }
        let device = endpoint.device
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnExclusiveAccess { throw ATKError.exclusiveAccess(product: endpoint.product) }
        if result == kIOReturnNotPermitted { throw ATKError.inputMonitoring }
        guard result == kIOReturnSuccess else { throw ATKError.openFailed(product: endpoint.product, code: result) }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, _, _, _, reportID, report, length in
            guard let context else { return }
            let channel = Unmanaged<HIDChannel>.fromOpaque(context).takeUnretainedValue()
            var bytes = Array(UnsafeBufferPointer(start: report, count: length))
            if channel.endpoint.usesCompx {
                if let reply = CompxPacket.reply(bytes, reportID: UInt8(truncatingIfNeeded: reportID)) {
                    if reply[1] == 0x0A {
                        channel.onEvent?(.other(reply[6]))
                    } else if reply[1] == channel.pendingCompxCommand {
                        channel.compxReplies.append(reply)
                    }
                }
                return
            }
            // macOS hands numbered reports over with the ID in front (64 bytes); add it if it is
            // missing. Not by looking for the command class: the mouse's own reports put a
            // checksum where replies have 0x72.
            if bytes.count <= Packet.size { bytes.insert(UInt8(truncatingIfNeeded: reportID), at: 0) }
            if let event = DeviceEvent(report: bytes) {
                channel.onEvent?(event)
            } else if let reply = Reply(report: bytes) {
                channel.replies.append(reply)
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        let runLoop = CFRunLoopGetCurrent()!
        self.runLoop = runLoop
        // In the common modes, so reports also arrive between requests on a thread that keeps its
        // run loop going (ATKBar's), not only while a reply is awaited.
        CFRunLoopAddCommonMode(runLoop, Self.replyMode)
        IOHIDDeviceScheduleWithRunLoop(device, runLoop, CFRunLoopMode.commonModes.rawValue)
    }

    public func close() {
        guard let runLoop else { return }
        // Callbacks pile up per device and outlive the close, so take ours off before this object goes away.
        IOHIDDeviceRegisterInputReportCallback(endpoint.device, buffer, 64, nil, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceUnscheduleFromRunLoop(endpoint.device, runLoop, CFRunLoopMode.commonModes.rawValue)
        IOHIDDeviceClose(endpoint.device, IOOptionBits(kIOHIDOptionsTypeNone))
        self.runLoop = nil
    }

    public func transfer(_ command: Command, target: Packet.Target, payload: [UInt8] = []) throws -> Reply {
        guard !endpoint.usesCompx else { throw ATKError.unsupportedProtocolCommand(command) }
        try open()
        let report = [Packet.reportID] + Packet.request(command, target: target, payload: payload)
        for _ in 0..<Self.attempts {
            replies.removeAll()
            let result = report.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(endpoint.device, kIOHIDReportTypeOutput, CFIndex(Packet.reportID),
                                     $0.baseAddress!, $0.count)
            }
            if result == kIOReturnNotPermitted { throw ATKError.secureInput }
            guard result == kIOReturnSuccess else { throw ATKError.sendFailed(command, result) }
            let deadline = Date().addingTimeInterval(Self.timeout)
            while Date() < deadline {
                CFRunLoopRunInMode(Self.replyMode, 0.01, true)
                if let reply = replies.first(where: { $0.command == command.rawValue }) {
                    if reply.isError { throw ATKError.deviceRejected(command) }
                    return reply
                }
            }
        }
        throw ATKError.noReply(command)
    }

    /// Read-only Compx requests. Keep them separate from BitMouse commands and reply offsets.
    func readCompx(_ command: UInt8, describing operation: Command,
                   address: UInt16 = 0, length: UInt8 = 0) throws -> [UInt8] {
        try transferCompx(command, describing: operation, address: address, length: length)
    }

    func transferCompx(_ command: UInt8, describing operation: Command,
                       address: UInt16 = 0, length: UInt8 = 0, payload: [UInt8] = []) throws -> [UInt8] {
        guard endpoint.usesCompx else { throw ATKError.unsupportedProtocolCommand(operation) }
        try open()
        let report = CompxPacket.request(command, address: address, length: length, payload: payload)
        pendingCompxCommand = command
        defer { pendingCompxCommand = nil; compxReplies.removeAll() }
        for _ in 0..<Self.attempts {
            compxReplies.removeAll()
            let result = report.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(endpoint.device, kIOHIDReportTypeFeature, 8, $0.baseAddress!, $0.count)
            }
            if result == kIOReturnNotPermitted { throw ATKError.secureInput }
            guard result == kIOReturnSuccess else { throw ATKError.sendFailed(operation, result) }
            let deadline = Date().addingTimeInterval(Self.timeout)
            while Date() < deadline {
                CFRunLoopRunInMode(Self.replyMode, 0.01, true)
                if let reply = compxReplies.first(where: {
                    $0[1] == command && $0[3] == report[3] && $0[4] == report[4]
                }) {
                    guard reply[2] == 0 else { throw ATKError.deviceRejected(operation) }
                    return reply
                }
            }
        }
        throw ATKError.noReply(operation)
    }

}
