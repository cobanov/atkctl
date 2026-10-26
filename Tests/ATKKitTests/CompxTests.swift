@testable import ATKKit
import Testing

@Test func compxVersionRequestMatchesATKHub() {
    #expect(CompxPacket.request(0x1D) == [8, 0x1D, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x30])
    let read = CompxPacket.request(8, address: 0x1234, length: 10)
    #expect(Array(read[3...5]) == [0x12, 0x34, 10])
    #expect(read.reduce(0) { $0 + Int($1) } & 0xFF == 0x55)
}

@Test func compxRecordedRepliesKeepReportOffsets() {
    let receiver: [UInt8] = [8, 0x1D, 0, 0, 0, 2, 1, 0x75, 0, 0, 0, 0, 0, 0, 0, 0, 0xB8]
    #expect(CompxPacket.reply(receiver, reportID: 8) == receiver)
    #expect(CompxPacket.reply(Array(receiver.dropFirst()), reportID: 8) == receiver)
    #expect(CompxPacket.version(receiver) == "1.75")
    #expect(CompxPacket.reply(Array(receiver.prefix(10)), reportID: 8) == nil)
    #expect(CompxPacket.reply(receiver, reportID: 7) == nil)
    var corrupt = receiver
    corrupt[6] = 0
    #expect(CompxPacket.reply(corrupt, reportID: 8) == nil)
}

@Test func compxRecordedA9UltraDPIStages() {
    let recorded: [[UInt8]] = [[0x3F, 0x3F, 0x44, 0x93], [0x7F, 0x7F, 0x88, 0xCF],
                                [0xBF, 0xBF, 0xCC, 0x0B], [0x37, 0x37, 0x22, 0xC5]]
    for (bytes, expected) in zip(recorded, [3200, 6400, 9600, 12800]) {
        let dpi = CompxMouse.decodeDPI(bytes)
        #expect(dpi.x == expected)
        #expect(dpi.y == expected)
        #expect(CompxMouse.encodeDPI(expected) == bytes)
    }
    // Different axes and multiplier flags must be decoded independently.
    let split = CompxMouse.decodeDPI([0x3F, 0x7F, 0x84])
    #expect(split.x == 3200)
    #expect(split.y == 6400)
    for value in stride(from: 50, through: 26000, by: 50) {
        let encoded = CompxMouse.encodeDPI(value)
        let decoded = CompxMouse.decodeDPI(encoded)
        #expect(decoded.x == value && decoded.y == value)
        #expect(encoded.reduce(0) { $0 + Int($1) } & 0xFF == 0x55)
    }
}

@Test func compxWriteOnlyContainsRequestedField() {
    let report = CompxPacket.request(7, address: 169, length: 2, payload: [4, 81])
    #expect(Array(report[1...7]) == [7, 0, 0, 169, 2, 4, 81])
    #expect(report[8..<16].allSatisfy { $0 == 0 })
    #expect(report.reduce(0) { $0 + Int($1) } & 0xFF == 0x55)
}
