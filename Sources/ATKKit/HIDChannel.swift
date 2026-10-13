import Foundation
import IOKit.hid

/// One ATK / VXE device as macOS sees it: the HID interface that carries usage page 0xFF05.
public struct Endpoint {
    public let device: IOHIDDevice
    public let productID: Int
    public let product: String
    public let manufacturer: String
    public let locationID: Int

    public var model: Catalog.Model? { Catalog.models[productID] }
    public var isReceiver: Bool { model?.kind == .receiver }
    public var isTested: Bool { Catalog.tested.contains(productID) }

    // Kept alive for the life of the process so the devices it hands out stay valid.
    nonisolated(unsafe) private static let manager: IOHIDManager = {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: Catalog.vendorID] as CFDictionary)
        // Without opening the manager, macOS refuses reports to devices that also expose a keyboard usage.
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        return manager
    }()

    /// Every connected device that speaks the protocol, mice first.
    public static func discover() -> [Endpoint] {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return devices.compactMap { device -> Endpoint? in
            let pairs = property(device, kIOHIDDeviceUsagePairsKey) as? [[String: Int]] ?? []
            guard pairs.contains(where: { $0[kIOHIDDeviceUsagePageKey] == 0xFF05 }) else { return nil }
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
    case openFailed(product: String, code: IOReturn)
    case sendFailed(Command, IOReturn)
    case noReply(Command)
    case deviceRejected(Command)
    case notConnected(String)
    case invalidValue(String)

    public var description: String {
        switch self {
        case .exclusiveAccess(let p):
            return "\(p) is held exclusively by another process (often Karabiner-Elements); run `atkctl doctor`"
        case .secureInput:
            return "macOS is blocking keyboard-class devices because Secure Input is on (screen locked or a password field focused); unlock and try again"
        case .openFailed(let p, let code): return "could not open \(p): IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16))"
        case .sendFailed(let c, let code): return "sending \(c) failed: IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16))"
        case .noReply(let c): return "no reply to \(c)"
        case .deviceRejected(let c): return "the device rejected \(c)"
        case .notConnected(let what): return what
        case .invalidValue(let what): return what
        }
    }
}

/// Request/reply over output and input report 8, the way ATK Hub does it:
/// a reply belongs to the request whose command byte it echoes.
public final class HIDChannel {
    public let endpoint: Endpoint
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var replies: [Reply] = []
    private var isOpen = false

    public static let timeout: TimeInterval = 0.5
    public static let attempts = 3

    public init(_ endpoint: Endpoint) {
        self.endpoint = endpoint
    }

    deinit {
        close()
        buffer.deallocate()
    }

    public func open() throws {
        guard !isOpen else { return }
        let device = endpoint.device
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnExclusiveAccess { throw ATKError.exclusiveAccess(product: endpoint.product) }
        guard result == kIOReturnSuccess else { throw ATKError.openFailed(product: endpoint.product, code: result) }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, _, _, _, reportID, report, length in
            guard let context else { return }
            let channel = Unmanaged<HIDChannel>.fromOpaque(context).takeUnretainedValue()
            var bytes = Array(UnsafeBufferPointer(start: report, count: length))
            // macOS hands numbered reports over with the ID in front; keep that shape either way.
            if bytes.first != UInt8(truncatingIfNeeded: reportID) || bytes.dropFirst().first != Packet.commandClass {
                bytes.insert(UInt8(truncatingIfNeeded: reportID), at: 0)
            }
            if let reply = Reply(report: bytes) { channel.replies.append(reply) }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        isOpen = true
    }

    public func close() {
        guard isOpen else { return }
        IOHIDDeviceUnscheduleFromRunLoop(endpoint.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(endpoint.device, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = false
    }

    public func transfer(_ command: Command, target: Packet.Target, payload: [UInt8] = []) throws -> Reply {
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
                CFRunLoopRunInMode(.defaultMode, 0.01, true)
                if let reply = replies.first(where: { $0.command == command.rawValue }) {
                    if reply.isError { throw ATKError.deviceRejected(command) }
                    return reply
                }
            }
        }
        throw ATKError.noReply(command)
    }
}
