import Foundation

/// Compx transport used by the 0x111A receiver (ATK Hub 3.2.29).
/// Report 8 contains 16 bytes: command, status, big-endian EEPROM address,
/// payload length, ten payload bytes, checksum. The report ID participates in the checksum.
enum CompxPacket {
    static func request(_ command: UInt8, address: UInt16 = 0, length: UInt8 = 0, payload: [UInt8] = []) -> [UInt8] {
        precondition(payload.count <= 10 && length <= 10)
        var bytes = [UInt8](repeating: 0, count: 17)
        bytes[0] = 8
        bytes[1] = command
        bytes[3] = UInt8(address >> 8)
        bytes[4] = UInt8(address & 0xFF)
        bytes[5] = length
        for (index, value) in payload.enumerated() { bytes[6 + index] = value }
        bytes[16] = UInt8(truncatingIfNeeded: 85 - bytes.prefix(16).reduce(0) { $0 + Int($1) })
        return bytes
    }

    /// Normalise macOS reports to include the report ID, rejecting truncated/corrupt replies.
    static func reply(_ bytes: [UInt8], reportID: UInt8) -> [UInt8]? {
        guard reportID == 8 else { return nil }
        let report = bytes.count == 16 ? [reportID] + bytes : bytes
        guard report.count == 17, report[0] == 8, report[5] <= 10,
              report.reduce(0, { $0 + Int($1) }) & 0xFF == 85 else { return nil }
        return report
    }

    static func version(_ reply: [UInt8]) -> String {
        String(format: "%x.%02x", reply[6], reply[7])
    }
}
