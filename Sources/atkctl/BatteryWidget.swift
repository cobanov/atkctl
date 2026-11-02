import ATKKit
import Foundation
import IOKit.hid
import Darwin

private var batteryWidgetStopped: sig_atomic_t = 0

/// All HID calls and callbacks run on this thread. Callbacks only mark pending work:
/// issuing a request from an input report callback would nest the HID reply loop.
final class BatteryWidget {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private var needsRescan = true
    private var needsRefresh = false
    private var session: Session?
    private var modelID: Int?
    private var nextRead = Date.distantPast
    private var lastRead = Date.distantPast
    private var lastError: String?

    func run() throws {
        let publisher = try BatteryPowerSource()
        batteryWidgetStopped = 0
        let oldInterrupt = signal(SIGINT) { _ in batteryWidgetStopped = 1 }
        let oldTerminate = signal(SIGTERM) { _ in batteryWidgetStopped = 1 }
        let runLoop = CFRunLoopGetCurrent()!
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: Catalog.vendorID] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<BatteryWidget>.fromOpaque(context).takeUnretainedValue().needsRescan = true
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<BatteryWidget>.fromOpaque(context).takeUnretainedValue().needsRescan = true
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
        defer {
            session = nil
            publisher.remove()
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, runLoop, CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            signal(SIGINT, oldInterrupt)
            signal(SIGTERM, oldTerminate)
            log("Stopped; removed system battery entry.")
        }
        log("Watching HID devices; publishing to the macOS battery widget. Ctrl+C to stop.")
        while batteryWidgetStopped == 0 {
            if needsRescan {
                needsRescan = false
                session = nil // close existing channels before replacing the discovery manager
                modelID = nil
                let endpoints = Endpoint.discover(rescan: true)
                session = endpoints.isEmpty ? nil : Session(endpoints: endpoints)
                // A sleeping/offline mouse behind a connected receiver still owns its
                // last reading. Remove it only when discovery finds no supported HID device.
                if endpoints.isEmpty { publisher.remove() }
                session?.onEvent = { [weak self] _ in self?.needsRefresh = true }
                nextRead = .distantPast
            }
            let now = Date()
            if now >= nextRead || (needsRefresh && now.timeIntervalSince(lastRead) >= 1) {
                needsRefresh = false
                lastRead = now
                do {
                    guard let session else { throw ATKError.notConnected("No ATK / VXE device; waiting for connection.") }
                    let battery = try session.battery()
                    if modelID == nil { modelID = session.mouseProductID() }
                    let name = session.mouse?.endpoint.product
                        ?? modelID.flatMap { Catalog.models[$0]?.name } ?? "ATK mouse"
                    let details = try BatteryPowerSourceDetails(name: name,
                        productID: modelID ?? session.receiver?.endpoint.productID ?? 0,
                        battery: battery, wired: session.mouse != nil)
                    if try publisher.update(details) {
                        log("\(name): \(battery.percent)%\(battery.charging ? " charging" : "")")
                    }
                    lastError = nil
                    nextRead = Date().addingTimeInterval(60)
                } catch {
                    // Keep the last successful reading on transient errors or mouse sleep.
                    // Physical removal is handled by the hotplug rescan above.
                    let message = String(describing: error)
                    if message != lastError { log("\(message); retrying."); lastError = message }
                    // Keep the channel listening for wake/reconnect events. Hotplug rebuilds it.
                    nextRead = Date().addingTimeInterval(5)
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("atkctl: \(message)\n".utf8))
    }
}
