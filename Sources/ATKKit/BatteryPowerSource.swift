import Foundation
import IOKit
import Darwin

/// One logical mouse, even when it switches between its cable and receiver.
/// Session currently selects one mouse; this identifier intentionally represents that slot.
public struct BatteryPowerSourceDetails {
    public let values: [String: Any]

    public init(name: String, productID: Int, battery: Battery, wired: Bool) throws {
        guard (0...100).contains(battery.percent) else {
            throw ATKError.invalidValue("battery percentage outside 0...100: \(battery.percent)")
        }
        values = [
            "Type": "Accessory Source", "Name": name,
            "Accessory Identifier": "dev.cobanov.atkctl.mouse",
            "Transport Type": "USB", "Accessory Category": "Mouse",
            "Is Present": true, "Is Charging": battery.charging,
            "Power Source State": wired || battery.charging ? "AC Power" : "Battery Power",
            "Current Capacity": battery.percent, "Max Capacity": 100,
            "Vendor ID": Catalog.vendorID, "Product ID": productID,
        ]
    }
}

/// Private IOKit publishing API, resolved at runtime so an OS change fails gracefully.
public final class BatteryPowerSource {
    private typealias Create = @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> IOReturn
    private typealias SetDetails = @convention(c) (UnsafeMutableRawPointer, CFDictionary) -> IOReturn
    private typealias Release = @convention(c) (UnsafeMutableRawPointer) -> IOReturn
    private let create: Create
    private let setDetails: SetDetails
    private let release: Release
    private var source: UnsafeMutableRawPointer?
    private var previous: NSDictionary?

    public init() throws {
        // IOKit is already linked; RTLD_DEFAULT searches the loaded images.
        let handle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let c = dlsym(handle, "IOPSCreatePowerSource"),
              let s = dlsym(handle, "IOPSSetPowerSourceDetails"),
              let r = dlsym(handle, "IOPSReleasePowerSource") else {
            throw ATKError.invalidValue("this macOS version does not provide the accessory battery publishing API")
        }
        create = unsafeBitCast(c, to: Create.self)
        setDetails = unsafeBitCast(s, to: SetDetails.self)
        release = unsafeBitCast(r, to: Release.self)
    }

    /// Returns true only when a changed reading was published.
    @discardableResult public func update(_ details: BatteryPowerSourceDetails) throws -> Bool {
        let dictionary = details.values as NSDictionary
        if previous?.isEqual(dictionary) == true { return false }
        if source == nil { try check(create(&source), operation: "create") }
        guard let source else { throw ATKError.invalidValue("IOPS returned no power source") }
        try check(setDetails(source, details.values as CFDictionary), operation: "publish")
        previous = dictionary
        return true
    }

    public func remove() {
        if let source { _ = release(source) }
        source = nil
        previous = nil
    }

    deinit { remove() }

    private func check(_ result: IOReturn, operation: String) throws {
        guard result == kIOReturnSuccess else {
            throw ATKError.invalidValue("cannot \(operation) accessory battery: 0x\(String(UInt32(bitPattern: result), radix: 16))")
        }
    }
}
