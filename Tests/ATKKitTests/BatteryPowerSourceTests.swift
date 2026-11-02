@testable import ATKKit
import Testing

@Test func batteryWidgetDistinguishesFullWiredBatteryFromDischarging() throws {
    let full = Battery(percent: 100, charging: false)
    let wired = try BatteryPowerSourceDetails(name: "Mouse", productID: 0x1119, battery: full, wired: true).values
    let wireless = try BatteryPowerSourceDetails(name: "Mouse", productID: 0x1119, battery: full, wired: false).values
    #expect(wired["Is Charging"] as? Bool == false)
    #expect(wired["Power Source State"] as? String == "AC Power")
    #expect(wireless["Power Source State"] as? String == "Battery Power")
    #expect(wired["Accessory Identifier"] as? String == wireless["Accessory Identifier"] as? String)
}

@Test func batteryWidgetRecognizesChargingThroughReceiver() throws {
    let details = try BatteryPowerSourceDetails(name: "Mouse", productID: 0x1119,
        battery: Battery(percent: 40, charging: true), wired: false).values
    #expect(details["Is Charging"] as? Bool == true)
    #expect(details["Power Source State"] as? String == "AC Power")
    #expect(details["Current Capacity"] as? Int == 40)
}

@Test func batteryWidgetRejectsInvalidDeviceReadings() {
    for percent in [-1, 101, 255] {
        #expect(throws: ATKError.self) {
            try BatteryPowerSourceDetails(name: "Mouse", productID: 0x1119,
                battery: Battery(percent: percent, charging: false), wired: false)
        }
    }
}
