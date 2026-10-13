/// Wire format of the vendor channel (HID usage page 0xFF05, output report 8).
///
/// Every request is 63 bytes after the report ID:
///
///     0  checksum   sum of bytes 1...62, low byte
///     1  0x72       command class
///     2  paramLen   cmdLen + 2
///     3  sequence   always 0
///     4  target     0 = the device itself, 1 = the mouse behind a receiver
///     5  command
///     6  cmdLen     bytes of payload
///     7… payload
///
/// Replies arrive as input report 8 with the same layout; byte 2 is 0xFF on error
/// and the value starts at byte 7.
public enum Packet {
    public static let reportID: UInt8 = 8
    public static let size = 63
    public static let commandClass: UInt8 = 0x72
    public static let payloadOffset = 7

    public enum Target: UInt8, Sendable {
        case device = 0
        case mouseBehindReceiver = 1
    }

    public static func request(_ command: Command, target: Target, payload: [UInt8] = []) -> [UInt8] {
        precondition(payload.count <= size - payloadOffset, "payload too long")
        var p = [UInt8](repeating: 0, count: size)
        p[1] = commandClass
        p[2] = command.paramLength
        p[4] = target.rawValue
        p[5] = command.rawValue
        p[6] = command.payloadLength
        for (i, byte) in payload.enumerated() { p[payloadOffset + i] = byte }
        p[0] = UInt8(truncatingIfNeeded: p[1...].reduce(0) { $0 + Int($1) })
        return p
    }
}

/// A reply, normalised so byte 0 is the report ID and offsets match `Packet`.
public struct Reply: Sendable, Equatable {
    public let bytes: [UInt8]

    public init?(report: [UInt8]) {
        guard report.count > Packet.payloadOffset, report[0] == Packet.reportID else { return nil }
        bytes = report
    }

    public var command: UInt8 { bytes[5] }
    public var isError: Bool { bytes[2] == 0xFF }

    public func u8(_ offset: Int) -> UInt8 {
        let i = Packet.payloadOffset + offset
        return i < bytes.count ? bytes[i] : 0
    }

    public func u16(_ offset: Int) -> UInt16 {
        UInt16(u8(offset)) | UInt16(u8(offset + 1)) << 8
    }

    public func u32(_ offset: Int) -> UInt32 {
        UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16
    }

    public func payload(_ range: Range<Int>) -> [UInt8] {
        range.map { u8($0) }
    }
}
