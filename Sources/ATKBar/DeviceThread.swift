import ATKKit
import Foundation
import IOKit.hid

/// A thread with its own run loop. HID channels must be opened and used on one thread,
/// so every request to the mouse runs here, one after another.
final class DeviceThread: Thread {
    private var runLoop: CFRunLoop!
    private let ready = DispatchSemaphore(value: 0)

    override init() {
        super.init()
        name = "ATKBar device"
        start()
        ready.wait()
    }

    override func main() {
        runLoop = CFRunLoopGetCurrent()
        RunLoop.current.add(Port(), forMode: .default)  // keeps the run loop alive while idle
        ready.signal()
        while !isCancelled { RunLoop.current.run(mode: .default, before: .distantFuture) }
    }

    func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }
}

/// What the panel shows, read in one go.
struct Snapshot {
    var receiverName: String?
    var receiverFirmware: String?
    var receiverConnected = false
    /// The mouse did not answer; the mouse values are the last ones read.
    var asleep = false
    var mouseName = "ATK mouse"
    /// The mouse's model, also when it is reached through the receiver.
    var modelPID: Int?
    var mouseFirmware: String?
    var battery: Battery?
    var link: ConnectionType?
    var config: MouseConfig?
    var dpi: DPITable?

    var hasMouse: Bool { config != nil }
}

/// Owns the session. Only ever touched on the device thread.
final class Backend {
    private var session: Session?
    /// Asked once per session: the model does not change while the receiver stays plugged in.
    private var identified: Int??
    /// Called on the device thread when the mouse reports a change of its own, such as a press
    /// of its DPI button.
    var onEvent: ((DeviceEvent) -> Void)?

    func read(rescan: Bool) throws -> Snapshot {
        if rescan || session == nil {
            session = nil  // close the old channels before the old manager goes
            identified = nil
            let endpoints = Endpoint.discover(rescan: true)
            session = endpoints.isEmpty ? nil : Session(endpoints: endpoints)
            session?.onEvent = { [weak self] in self?.onEvent?($0) }
        }
        guard let s = session else { throw ATKError.notConnected("No ATK or VXE mouse found. Plug in the receiver, or connect the mouse with its cable.") }
        do {
            var snap = Snapshot()
            if let receiver = s.receiver {
                snap.receiverName = receiver.endpoint.product
                snap.receiverFirmware = try s.receiverVersion()
                snap.receiverConnected = try s.receiverStatus().connected
                if !snap.receiverConnected && s.mouse == nil { return snap }
            }
            snap.mouseFirmware = try s.firmwareVersion()
            if identified == nil { identified = .some(s.mouseProductID()) }
            snap.modelPID = identified ?? nil
            if let mouse = s.mouse {
                snap.mouseName = mouse.endpoint.product
            } else if let pid = snap.modelPID, let model = Catalog.models[pid] {
                snap.mouseName = model.name
            }
            snap.battery = try s.battery()
            snap.link = try? s.connectionType()
            snap.config = try s.config()
            snap.dpi = try s.dpiTable()
            return snap
        } catch ATKError.secureInput {
            throw ATKError.secureInput
        } catch {
            session = nil  // look for the devices again next time
            throw error
        }
    }

    func apply(_ change: (Session) throws -> Void) throws -> Snapshot {
        if session == nil { _ = try read(rescan: true) }
        guard let session else { throw ATKError.notConnected("No ATK or VXE mouse found. Plug in the receiver, or connect the mouse with its cable.") }
        try change(session)
        return try read(rescan: false)
    }
}

/// Calls back when an ATK / VXE device is plugged in or removed.
final class HotPlug {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: Catalog.vendorID] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            Unmanaged<HotPlug>.fromOpaque(context!).takeUnretainedValue().onChange()
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            Unmanaged<HotPlug>.fromOpaque(context!).takeUnretainedValue().onChange()
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
    }
}
