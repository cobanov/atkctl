/// Commands of the ATK / VXE "BitMouse" protocol, with the length fields ATK Hub sends.
public enum Command: UInt8, Sendable, CaseIterable {
    // mouse
    case setReportRate = 0x01
    case setDPI = 0x02
    case setLiftOff = 0x03
    case getBatteryLevel = 0x07
    case getCurrentConfig = 0x09
    case setLinearCorrection = 0x0B
    case setRippleControl = 0x0C
    case setMotionSync = 0x0D
    case getChargingStatus = 0x0F
    case setSleepTime = 0x15
    case setDebounceTime = 0x16
    case getAddressData = 0x17
    case getDeviceType = 0x1A
    case getFirmwareVersion = 0x1C
    case getMouseID = 0x4A
    case getChargeRemainingTime = 0xAE
    // receiver
    case getReceiverConnectStatus = 0x81
    case startPairing = 0x82
    case clearPairing = 0x83
    case getPairStatus = 0x84
    case getReceiverVersion = 0x88
    /// The mouse's ID as the receiver knows it; sent like a mouse command.
    case getMouseIDViaReceiver = 0x89

    /// ATK Hub's (`paramLen`, `cmdLen`). They do not follow one rule, so they are listed as sent.
    var lengths: (param: UInt8, payload: UInt8) {
        switch self {
        case .getBatteryLevel, .getChargingStatus, .getDeviceType: return (2, 1)
        case .setReportRate, .setLinearCorrection, .setRippleControl, .setMotionSync, .setDebounceTime,
             .getReceiverConnectStatus, .getPairStatus:
            return (3, 1)
        case .startPairing, .clearPairing: return (3, 0)
        case .setLiftOff: return (4, 2)
        case .setSleepTime: return (5, 2)
        case .getFirmwareVersion, .getReceiverVersion: return (5, 3)
        case .getChargeRemainingTime: return (6, 4)
        case .getAddressData: return (10, 13)
        case .getMouseID, .getMouseIDViaReceiver: return (8, 6)
        case .setDPI: return (12, 10)
        case .getCurrentConfig: return (19, 17)
        }
    }

    public var paramLength: UInt8 { lengths.param }
    public var payloadLength: UInt8 { lengths.payload }

    /// Commands the receiver answers itself rather than forwarding to the mouse.
    public var isReceiverCommand: Bool {
        switch self {
        case .getReceiverConnectStatus, .startPairing, .clearPairing, .getPairStatus, .getReceiverVersion,
             .getDeviceType:
            return true
        default:
            return false
        }
    }
}
