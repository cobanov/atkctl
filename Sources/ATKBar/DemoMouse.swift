import ATKKit

/// A mouse that lives only in memory, for trying the panel without one plugged in and for
/// `--render-preview`. Its state is encoded into the same bytes a real A9 Plus NK sends,
/// so the panel reads it through the real parsers.
struct DemoMouse {
    var activeStage = 2
    var stages: [(dpi: Int, rgb: Int)] = [(400, 0xFF0000), (800, 0x00FF00), (1600, 0x0000FF), (3200, 0xFF00FF)]
    var rate = ReportRate.hz1000
    var liftOffLevel = 6
    var motionSync = true
    var angleSnapping = false
    var ripple = false
    var sleepSeconds = 120
    var debounceMs = 4
    var battery = 86

    var snapshot: Snapshot {
        var snap = Snapshot()
        snap.receiverName = "NK mouse NANO dongle"
        snap.receiverFirmware = "1.0.19"
        snap.receiverConnected = true
        snap.mouseName = "ATK A9 Plus"
        snap.mouseFirmware = "1.0.14"
        snap.battery = Battery(percent: battery, charging: false)
        snap.link = .receiver1K

        var config = [UInt8](repeating: 0, count: 17)
        config[2] = rate.code
        config[3] = 1
        config[5] = UInt8(liftOffLevel - 1)
        config[6] = motionSync ? 1 : 0
        config[7] = angleSnapping ? 1 : 0
        config[8] = ripple ? 1 : 0
        config[9] = UInt8(sleepSeconds & 0xFF)
        config[10] = UInt8(sleepSeconds >> 8)
        config[11] = UInt8(debounceMs)
        snap.config = MouseConfig(Reply(report: [0x08, 0x72, 0x00, 0x15, 0x00, 0x09, 0x11] + config)!)

        var table: [UInt8] = [UInt8(activeStage), 8]
        for slot in 0..<8 {
            guard slot < stages.count else { table += [UInt8](repeating: 0, count: 8); continue }
            let (dpi, rgb) = stages[slot]
            let lo = UInt8(dpi & 0xFF), hi = UInt8(dpi >> 8)
            table += [lo, hi, lo, hi, UInt8(rgb & 0xFF), UInt8(rgb >> 8 & 0xFF), UInt8(rgb >> 16), 0]
        }
        snap.dpi = DPITable(table + [0, 0, 0, 0])
        return snap
    }
}
