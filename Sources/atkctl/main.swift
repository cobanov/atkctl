import ATKKit
import Foundation

let version = "0.1.0"

let usage = """
atkctl \(version): configure ATK / VXE mice on macOS, without ATK Hub

usage:
  atkctl [status] [--json]       mouse and receiver: firmware, battery, settings
  atkctl dpi                     DPI stages
  atkctl set <setting> <value>   change a setting, then read it back
  atkctl pair [--yes]            pair the mouse with the plugged-in receiver
  atkctl doctor [--fix-karabiner]  find what stops the mouse or ATK Hub working
  atkctl list                    connected devices

settings:
  sleep            30s 1m 2m 3m 5m 20m 25m 30m
  polling          125 250 500 1000 2000 4000 8000
  debounce         0 1 2 4 8 15 20   (ms)
  motion-sync      on | off
  ripple           on | off
  angle-snapping   on | off
  dpi              <stage> <value>   e.g. `atkctl set dpi 2 1600`
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("atkctl: \(message)\n".utf8))
    exit(1)
}

func onOff(_ value: String) -> Bool {
    switch value.lowercased() {
    case "on", "true", "1", "yes": return true
    case "off", "false", "0", "no": return false
    default: fail("expected on or off, got \(value)")
    }
}

func parseSeconds(_ value: String) -> Int {
    let v = value.lowercased()
    if v.hasSuffix("min"), let n = Int(v.dropLast(3)) { return n * 60 }
    if v.hasSuffix("m"), let n = Int(v.dropLast()) { return n * 60 }
    if v.hasSuffix("s"), let n = Int(v.dropLast()) { return n }
    if let n = Int(v) { return n }
    fail("cannot read \(value) as a duration, e.g. 30s or 2m")
}

func duration(_ seconds: Int) -> String {
    seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
}

func session() -> Session {
    let s = Session()
    if s.isEmpty { fail("no ATK / VXE mouse or receiver found") }
    return s
}

func attempt<T>(_ body: () throws -> T) -> T? {
    do { return try body() } catch { return nil }
}

func status(json: Bool) {
    let s = session()
    var out: [String: Any] = [:]
    var lines: [String] = []

    if let r = s.receiver {
        let version = attempt { try s.receiverVersion() }
        let st = attempt { try s.receiverStatus() }
        out["receiver"] = ["name": r.endpoint.product, "firmware": version as Any,
                           "connected": st?.connected as Any, "paired": st?.paired as Any]
        let state = st.map { $0.connected ? "connected" : ($0.paired ? "paired, mouse not connected" : "not paired") } ?? "?"
        lines.append(pad(r.endpoint.product) + "firmware \(version ?? "?")   \(state)")
    }

    let name = s.mouse?.endpoint.product ?? "mouse (via receiver)"
    do {
        let firmware = try s.firmwareVersion()
        let battery = try s.battery()
        let config = try s.config()
        let link = attempt { try s.connectionType() } ?? nil
        out["mouse"] = [
            "name": name, "firmware": firmware, "battery": battery.percent, "charging": battery.charging,
            "connection": link?.label as Any, "polling_hz": config.reportRate?.rawValue as Any, "dpi": config.dpi,
            "lift_off_level": config.liftOffLevel, "motion_sync": config.motionSync,
            "angle_snapping": config.angleSnapping, "ripple": config.rippleControl,
            "sleep_seconds": config.sleepSeconds, "debounce_ms": config.debounceMs,
        ]
        lines.append(pad(name) + "firmware \(firmware)   battery \(battery.percent)%\(battery.charging ? " charging" : "")"
                     + (link.map { "   \($0.label)" } ?? ""))
        lines.append("")
        lines.append("  polling         \(config.reportRate.map { "\($0.rawValue) Hz" } ?? "?")")
        lines.append("  dpi             \(config.dpi)")
        lines.append("  lift-off level  \(config.liftOffLevel)")
        lines.append("  sleep           \(duration(config.sleepSeconds))")
        lines.append("  debounce        \(config.debounceMs) ms")
        lines.append("  motion-sync     \(config.motionSync ? "on" : "off")")
        lines.append("  ripple          \(config.rippleControl ? "on" : "off")")
        lines.append("  angle-snapping  \(config.angleSnapping ? "on" : "off")")
    } catch {
        out["mouse_error"] = "\(error)"
        lines.append(pad(name) + "not reachable: \(error)")
    }

    if json {
        let data = try! JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } else {
        print(lines.joined(separator: "\n"))
    }
}

func pad(_ s: String) -> String { s.padding(toLength: max(s.count + 3, 26), withPad: " ", startingAt: 0) }

func dpi() {
    let s = session()
    do {
        let table = try s.dpiTable()
        for (i, stage) in table.stages.enumerated() {
            let axes = stage.x == stage.y ? "\(stage.x)" : "\(stage.x) x \(stage.y)"
            let hex = String(format: "#%02X%02X%02X", stage.color.r, stage.color.g, stage.color.b)
            print("\(i == table.activeIndex ? "*" : " ") \(i + 1)  \(axes.padding(toLength: 12, withPad: " ", startingAt: 0))\(hex)")
        }
    } catch {
        fail("\(error)")
    }
}

func set(_ args: [String]) {
    guard args.count >= 2 else { fail("usage: atkctl set <setting> <value>; see `atkctl help`") }
    let s = session()
    do {
        switch args[0] {
        case "sleep":
            try s.setSleep(seconds: parseSeconds(args[1]))
            print("sleep \(duration(try s.config().sleepSeconds))")
        case "polling", "report-rate":
            guard let hz = Int(args[1].lowercased().replacingOccurrences(of: "hz", with: "")),
                  let rate = ReportRate(rawValue: hz) else { fail("polling must be 125, 250, 500, 1000, 2000, 4000 or 8000") }
            try s.setReportRate(rate)
            let now = try s.config().reportRate
            print("polling \(now.map { "\($0.rawValue) Hz" } ?? "?")" + (now == rate ? "" : " (the device did not take \(hz) Hz)"))
        case "debounce":
            guard let ms = Int(args[1].lowercased().replacingOccurrences(of: "ms", with: "")) else { fail("debounce is in ms") }
            try s.setDebounce(ms: ms)
            print("debounce \(try s.config().debounceMs) ms")
        case "motion-sync":
            try s.setMotionSync(onOff(args[1]))
            print("motion-sync \(try s.config().motionSync ? "on" : "off")")
        case "ripple":
            try s.setRippleControl(onOff(args[1]))
            print("ripple \(try s.config().rippleControl ? "on" : "off")")
        case "angle-snapping":
            try s.setAngleSnapping(onOff(args[1]))
            print("angle-snapping \(try s.config().angleSnapping ? "on" : "off")")
        case "dpi":
            guard args.count == 3, let stage = Int(args[1]), let value = Int(args[2]) else {
                fail("usage: atkctl set dpi <stage> <value>")
            }
            try s.setDPI(stage: stage - 1, to: value)
            let table = try s.dpiTable()
            print("dpi stage \(stage): \(table.stages[stage - 1].x)")
        default:
            fail("unknown setting \(args[0]); see `atkctl help`")
        }
    } catch {
        fail("\(error)")
    }
}

func pair(yes: Bool) {
    let s = session()
    guard s.receiver != nil else { fail("plug in the receiver first") }
    if !yes {
        print("This forgets the mouse the receiver is paired with now. Continue? [y/N] ", terminator: "")
        guard readLine()?.lowercased().hasPrefix("y") == true else { exit(1) }
    }
    print("""
    Switch the mouse on and unplug its cable. Then hold left, right and wheel-click
    together until its light blinks fast. Listening for 30 seconds…
    """)
    do {
        let ok = try s.pair { elapsed in
            print("\r  \(30 - Int(elapsed)) s ", terminator: "")
            fflush(stdout)
        }
        print(ok ? "\rpaired.          " : "\rno mouse answered; try again closer to the receiver.")
        if !ok { exit(1) }
    } catch {
        fail("\(error)")
    }
}

func doctor(fix: Bool) {
    var failed = false
    for f in Doctor.run(fixKarabiner: fix) {
        print("[\(f.level.rawValue.padding(toLength: 4, withPad: " ", startingAt: 0))] \(f.message)")
        if let hint = f.fix { print("       → \(hint)") }
        if f.level == .fail { failed = true }
    }
    if failed { exit(1) }
}

func list() {
    let endpoints = Endpoint.discover()
    if endpoints.isEmpty { fail("no ATK / VXE mouse or receiver found") }
    for e in endpoints {
        let kind = e.isReceiver ? "receiver" : "mouse"
        print("\(String(format: "0x%04X", e.productID))  \(kind.padding(toLength: 9, withPad: " ", startingAt: 0))"
              + "\(e.product) (\(e.manufacturer))\(e.isTested ? "" : "  [untested]")")
    }
}

var args = Array(CommandLine.arguments.dropFirst())
let flags = Set(args.filter { $0.hasPrefix("--") })
args.removeAll { $0.hasPrefix("--") }

switch args.first ?? "status" {
case "status": status(json: flags.contains("--json"))
case "dpi": dpi()
case "set": set(Array(args.dropFirst()))
case "pair": pair(yes: flags.contains("--yes"))
case "doctor": doctor(fix: flags.contains("--fix-karabiner"))
case "list": list()
case "version": print(version)
case "help": print(usage)
default:
    if flags.contains("--version") { print(version) } else { print(usage); exit(1) }
}
