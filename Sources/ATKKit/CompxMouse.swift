import Foundation

/// Settings layout for the PAW3950Ultra in the ATK A9 Ultra, from ATK Hub's Compx driver.
/// Other Compx mice can use different DPI encodings; do not apply this layout to them.
struct CompxMouse {
    let channel: HIDChannel

    func verifyModel() throws {
        let id = try channel.readCompx(0x10, describing: .getMouseID)
        guard id[6] == 2, id[7] == 87 else {
            throw ATKError.notConnected("this Compx mouse model is not supported; only ATK A9 Ultra settings are implemented")
        }
    }

    func read(_ address: UInt16, count: UInt8) throws -> [UInt8] {
        let reply = try channel.readCompx(8, describing: .getAddressData, address: address, length: count)
        guard reply[5] >= count else { throw ATKError.noReply(.getAddressData) }
        return Array(reply[6..<(6 + Int(count))])
    }

    static let rates: [UInt8: ReportRate] = [1: .hz1000, 2: .hz500, 4: .hz250, 8: .hz125,
                                            16: .hz2000, 32: .hz4000, 64: .hz8000]

    func config() throws -> MouseConfig {
        try verifyModel()
        let rate = try read(0, count: 6)
        let lod = try read(10, count: 2)
        let functions = try read(169, count: 10)
        let profile = try channel.readCompx(0x0E, describing: .getCurrentConfig)
        return MouseConfig(profile: Int(profile[6]), reportRate: Self.rates[rate[0]],
                           liftOffLevel: Int(lod[0]), motionSync: functions[2] != 0,
                           angleSnapping: functions[6] != 0, rippleControl: functions[8] != 0,
                           sleepSeconds: Int(functions[4]) * 10, debounceMs: Int(functions[0]))
    }

    static func decodeDPI(_ bytes: [UInt8]) -> (x: Int, y: Int) {
        let extra = Int(bytes[2])
        let x = Int(bytes[0]) | ((extra & 12) >> 2) << 8
        let y = Int(bytes[1]) | ((extra & 192) >> 6) << 8
        let baseX = extra & 2 != 0 ? x * 50 + 10050 : (x + 1) * 10
        let baseY = extra & 32 != 0 ? y * 50 + 10050 : (y + 1) * 10
        return (baseX * (extra & 1 != 0 ? 2 : 1), baseY * (extra & 16 != 0 ? 2 : 1))
    }

    static func encodeDPI(_ dpi: Int) -> [UInt8] {
        let high = dpi > 10000
        let doubled = dpi > 30000
        let base = high ? ((doubled ? dpi / 2 : dpi) - 10050) / 50 : dpi / 10 - 1
        let low = UInt8(truncatingIfNeeded: base)
        let upper = UInt8((base >> 8) & 3)
        let extra: UInt8 = (upper << 2) | (upper << 6) | (high ? 0x22 : 0) | (doubled ? 0x11 : 0)
        return [low, low, extra, UInt8(truncatingIfNeeded: 85 - Int(low) * 2 - Int(extra))]
    }

    func dpiTable() throws -> DPITable {
        try verifyModel()
        let settings = try read(0, count: 6)
        let count = Int(settings[2])
        let active = Int(settings[4]) - 1
        guard (1...8).contains(count), (0..<count).contains(active) else {
            throw ATKError.invalidValue("invalid DPI stage count/index reported by the Compx mouse")
        }
        var stages: [DPIStage] = []
        for index in 0..<count {
            let value = Self.decodeDPI(try read(UInt16(12 + index * 4), count: 4))
            let rgb = try read(UInt16(44 + index * 4), count: 4)
            stages.append(DPIStage(x: value.x, y: value.y, color: (rgb[0], rgb[1], rgb[2])))
        }
        return DPITable(activeIndex: active, stages: stages)
    }

    /// Write only the requested EEPROM field, preserving adjacent settings.
    func write(_ address: UInt16, bytes: [UInt8], operation: Command) throws {
        _ = try channel.transferCompx(7, describing: operation, address: address,
                                      length: UInt8(bytes.count), payload: bytes)
    }

    func setByte(_ address: UInt16, value: UInt8, operation: Command) throws {
        try verifyModel()
        try write(address, bytes: [value, UInt8(truncatingIfNeeded: 85 - Int(value))], operation: operation)
    }
}
