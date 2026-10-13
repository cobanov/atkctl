@testable import ATKKit
import Testing

/// Replies recorded from an ATK A9 Plus NK (firmware 1.0.14) and its NK NANO dongle (1.0.19).
enum Recorded {
    static let mouseFirmware: [UInt8] = [0x08, 0x72, 0x00, 0x3B, 0x00, 0x1C, 0x03, 0x01, 0x00, 0x0E, 0x41]
    static let mouseFirmwareViaReceiver: [UInt8] = [0x08, 0x72, 0x00, 0x07, 0x00, 0x1C, 0x03, 0x01, 0x00, 0x0E, 0x41]
    static let battery: [UInt8] = [0x08, 0x72, 0x00, 0x3B, 0x00, 0x07, 0x01, 0x64, 0x30, 0x11]
    static let receiverFirmware: [UInt8] = [0x08, 0x72, 0x00, 0x3B, 0x00, 0x88, 0x03, 0x01, 0x00, 0x13, 0x44]
    static let receiverConnected: [UInt8] = [0x08, 0x72, 0x00, 0x3B, 0x00, 0x81, 0x01, 0x01]
}

@Test func requestLayoutAndChecksum() {
    let p = Packet.request(.getFirmwareVersion, target: .device)
    #expect(p.count == 63)
    #expect(Array(p[1...6]) == [0x72, 5, 0, 0, 0x1C, 3])
    #expect(p[0] == UInt8((0x72 + 5 + 0x1C + 3) & 0xFF))
    #expect(p[7...].allSatisfy { $0 == 0 })
}

@Test func requestThroughReceiverCarriesTargetAndPayload() {
    let p = Packet.request(.setSleepTime, target: .mouseBehindReceiver, payload: [0x78, 0x00])
    #expect(Array(p[1...8]) == [0x72, 5, 0, 1, 0x15, 2, 0x78, 0x00])
    #expect(Int(p[0]) == (0x72 + 5 + 1 + 0x15 + 2 + 0x78) & 0xFF)
}

@Test func lengthsMatchWhatATKHubSends() {
    #expect(Command.getBatteryLevel.lengths == (2, 1))
    #expect(Command.setSleepTime.lengths == (5, 2))
    #expect(Command.getAddressData.lengths == (10, 13))
    #expect(Command.getCurrentConfig.lengths == (19, 17))
    #expect(Command.startPairing.lengths == (3, 0))
}

@Test func recordedRepliesParse() throws {
    let firmware = try #require(Reply(report: Recorded.mouseFirmware))
    #expect(firmware.command == Command.getFirmwareVersion.rawValue)
    #expect(!firmware.isError)
    #expect("\(firmware.u8(0)).\(firmware.u8(1)).\(firmware.u8(2))" == "1.0.14")

    let forwarded = try #require(Reply(report: Recorded.mouseFirmwareViaReceiver))
    #expect(forwarded.u8(2) == 14)

    #expect(try #require(Reply(report: Recorded.battery)).u8(0) == 100)
    let receiver = try #require(Reply(report: Recorded.receiverFirmware))
    #expect("\(receiver.u8(0)).\(receiver.u8(1)).\(receiver.u8(2))" == "1.0.19")
    #expect(try #require(Reply(report: Recorded.receiverConnected)).u8(0) == 1)
}

@Test func errorReplyIsDetected() throws {
    let reply = try #require(Reply(report: [0x08, 0x72, 0xFF, 0x00, 0x00, 0x1C, 0x03, 0x00]))
    #expect(reply.isError)
    #expect(Reply(report: [0x09, 0x72, 0x00, 0x00, 0x00, 0x1C, 0x03, 0x00]) == nil)
}

@Test func configFieldsComeFromTheirOffsets() throws {
    var bytes = [UInt8](repeating: 0, count: 64)
    bytes[0] = 0x08
    let fields: [Int: UInt8] = [0: 1, 2: 0, 3: 0x20, 4: 0x03, 5: 1, 6: 1, 7: 0, 8: 1, 9: 0x2C, 10: 0x01, 11: 8]
    for (offset, value) in fields { bytes[Packet.payloadOffset + offset] = value }
    let config = MouseConfig(try #require(Reply(report: bytes)))
    #expect(config.profile == 1)
    #expect(config.reportRate == .hz1000)
    #expect(config.dpi == 800)
    #expect(config.liftOffLevel == 2)
    #expect(config.motionSync && !config.angleSnapping && config.rippleControl)
    #expect(config.sleepSeconds == 300)
    #expect(config.debounceMs == 8)
}

@Test func dpiTableReadsStagesAndColours() {
    var bytes = [UInt8](repeating: 0, count: 70)
    bytes[0] = 1  // active stage
    bytes[1] = 2  // stage count
    bytes[2...9] = [0x20, 0x03, 0x20, 0x03, 0x00, 0x00, 0xFF, 0x00]  // 800, red
    bytes[10...17] = [0x40, 0x06, 0x80, 0x0C, 0xFF, 0x00, 0x00, 0x00]  // 1600 x 3200, blue
    let table = DPITable(bytes)
    #expect(table.activeIndex == 1)
    #expect(table.stages.count == 2)
    #expect(table.stages[0] == DPIStage(x: 800, y: 800, color: (r: 0xFF, g: 0, b: 0)))
    #expect(table.stages[1] == DPIStage(x: 1600, y: 3200, color: (r: 0, g: 0, b: 0xFF)))
}

@Test func reportRateCodesRoundTrip() {
    for rate in ReportRate.allCases { #expect(ReportRate(code: rate.code) == rate) }
    #expect(ReportRate.hz1000.code == 0)
    #expect(ReportRate.hz8000.code == 4)
}

@Test func catalogKnowsTheTestedPair() {
    #expect(Catalog.models[0x1263]?.kind == .mouse)
    #expect(Catalog.models[0x1216]?.kind == .receiver)
}
