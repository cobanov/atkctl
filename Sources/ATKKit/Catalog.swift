/// Devices ATK Hub drives with the BitMouse protocol (vendor 0x373B), taken from its device list.
/// Only the ATK A9 Plus NK (0x1263) and the NK NANO dongle (0x1216) have been tested.
public enum Catalog {
    public static let vendorID = 0x373B

    public enum Kind: Sendable { case mouse, receiver }

    public struct Model: Sendable {
        public let name: String
        public let kind: Kind
    }

    public static let models: [Int: Model] = [
        0x1154: Model(name: "ATK ZERO", kind: .mouse),
        0x1155: Model(name: "Wireless mouse 8k dongle-L1", kind: .receiver),
        0x11DB: Model(name: "ATK A9 Pro Max 2.0 NK", kind: .mouse),
        0x11DC: Model(name: "NK mouse 8K NANO dongle", kind: .receiver),
        0x1211: Model(name: "ATK A9 Ultimate 3.0", kind: .mouse),
        0x1213: Model(name: "VXE V3 NK", kind: .mouse),
        0x1214: Model(name: "VXE V3 PRO NK", kind: .mouse),
        0x1215: Model(name: "VXE V3 Plus", kind: .mouse),
        0x1216: Model(name: "NK mouse NANO dongle", kind: .receiver),
        0x1222: Model(name: "ATK A9 SE NK", kind: .mouse),
        0x1223: Model(name: "ATK A9 NK", kind: .mouse),
        0x1224: Model(name: "ATK A9 Plus NK", kind: .mouse),
        0x123A: Model(name: "ATK Ghost Ultimate", kind: .mouse),
        0x124C: Model(name: "VXE R1 NK", kind: .mouse),
        0x124D: Model(name: "VXE R1 S NK", kind: .mouse),
        0x124F: Model(name: "Wireless mouse 8k dongle-L0", kind: .receiver),
        0x1251: Model(name: "ATK A9 Mini +", kind: .mouse),
        0x1263: Model(name: "ATK A9 Plus NK", kind: .mouse),
        0x1264: Model(name: "ATK A9 Pro Max 2.0 NK", kind: .mouse),
        0x1268: Model(name: "ATK A9 Mini", kind: .mouse),
        0x127B: Model(name: "VXE V3 PRO Max", kind: .mouse),
        0x1287: Model(name: "ATK A9 Ultimate +", kind: .mouse),
        0x1288: Model(name: "ATK A9 Air +", kind: .mouse),
        0x128F: Model(name: "ATK A9 Ultra Max 2.0 +", kind: .mouse),
        0x1290: Model(name: "Wireless mouse 8k dongle-M1", kind: .receiver),
        0x1291: Model(name: "Wireless mouse 8k NANO dongle-M1", kind: .receiver),
        0x1299: Model(name: "ATK X1 SE Nearlink", kind: .mouse),
        0x129A: Model(name: "VXE R1 PRO MAX 2.0 NK", kind: .mouse),
        0x129E: Model(name: "ATK ZERO +", kind: .mouse),
        0x12AF: Model(name: "Wireless mouse 8k NANO dongle-L", kind: .receiver),
        0x12B1: Model(name: "VXE R2 SE NK", kind: .mouse),
        0x12CD: Model(name: "Wireless mouse 8k NANO dongle-M1", kind: .receiver),
        0x12CE: Model(name: "ATK PHANTOM ULTIMATE", kind: .mouse),
        0x12D0: Model(name: "ATK A9 NB ULTRA", kind: .mouse),
        0x12D1: Model(name: "Wireless mouse -8K TOWER dongle", kind: .receiver),
        0x12D2: Model(name: "VXE V3 NK", kind: .mouse),
        0x12D9: Model(name: "ATK X1 ULTIMATE 2.0+", kind: .mouse),
        0x12DC: Model(name: "VXE R1 SE+", kind: .mouse),
        0x12DE: Model(name: "ATK X1 Ultra Max 2.0 + Tri-Mode", kind: .mouse),
        0x12E1: Model(name: "VXE T1", kind: .mouse),
        0x12E3: Model(name: "ATK U2 Plus NK", kind: .mouse),
        0x12EA: Model(name: "Wireless mouse 8k dongle-G", kind: .receiver),
        0x12EC: Model(name: "ATK X1 Air+", kind: .mouse),
        0x12F1: Model(name: "ATK A9 Ultimate +", kind: .mouse),
        0x12F5: Model(name: "Wireless mouse 8k dongle-M1", kind: .receiver),
        0x1300: Model(name: "ATK A9 Plus NK", kind: .mouse),
        0x1301: Model(name: "ATK A9 Pro Max 2.0 NK", kind: .mouse),
        0x1302: Model(name: "Wireless mouse 8k dongle-O", kind: .receiver),
        0x1304: Model(name: "ATK F1 V3 ULTIMATE+", kind: .mouse),
        0x1305: Model(name: "ATK A9 3.0 NK", kind: .mouse),
        0x1306: Model(name: "VXE V3 PRO NK", kind: .mouse),
        0x1307: Model(name: "ATK F1 V3 Ultra Max", kind: .mouse),
        0x1308: Model(name: "ATK F1 V3 ULTIMATE+", kind: .mouse),
        0x130E: Model(name: "ATK X1 SE NK", kind: .mouse),
        0x130F: Model(name: "ATK A9 SE 3.0 NK", kind: .mouse),
        0x1310: Model(name: "VXE R1 S NK", kind: .mouse),
        0x1311: Model(name: "VXE R1N NK", kind: .mouse),
        0x1312: Model(name: "ATK PHANTOM ULTIMATE", kind: .mouse),
        0x1314: Model(name: "ATK A9 Ultimate", kind: .mouse),
        0x1315: Model(name: "Wireless mouse 8k NANO dongle-M1", kind: .receiver),
        0x1319: Model(name: "VXE R1 SE+", kind: .mouse),
        0x1332: Model(name: "Wireless mouse 8k dongle-G", kind: .receiver),
        0x1337: Model(name: "ATK A9 Plus 3.0 NK", kind: .mouse),
        0x1338: Model(name: "ATK A9 Pro Max 3.0 NK", kind: .mouse),
        0x133E: Model(name: "Wireless mouse 8k NANO dongle-A1", kind: .receiver),
        0x133F: Model(name: "Wireless mouse -1k dongle", kind: .receiver),
        0x1346: Model(name: "Wireless mouse 8k dongle-M1", kind: .receiver),
        0x1347: Model(name: "Wireless mouse 8k NANO dongle-M1", kind: .receiver),
        0x1348: Model(name: "Wireless mouse 8k NANO dongle-M1", kind: .receiver),
        0x134B: Model(name: "Wireless mouse 8k dongle", kind: .receiver),
    ]

    public static let tested: Set<Int> = [0x1263, 0x1216]
}
