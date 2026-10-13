import Foundation

/// Finds the things that stop the mouse or ATK Hub from working on macOS.
public enum Doctor {
    public enum Level: String, Sendable { case ok = "ok", warn = "warn", fail = "FAIL" }

    public struct Finding: Sendable {
        public let level: Level
        public let message: String
        public let fix: String?
    }

    public static func run(fixKarabiner: Bool = false) -> [Finding] {
        var findings: [Finding] = []
        let endpoints = Endpoint.discover()
        if endpoints.isEmpty {
            return [Finding(level: .fail, message: "no ATK / VXE mouse or receiver found",
                            fix: "plug in the receiver, or connect the mouse with its cable")]
        }

        if let owner = secureInputOwner() {
            let locked = owner.hasSuffix("loginwindow")
            findings.append(Finding(
                level: .warn,
                message: "Secure Input is on (\(locked ? "screen is locked" : owner)); macOS refuses reports to receivers that also act as keyboards",
                fix: locked ? "unlock the Mac" : "leave the password field or quit \(owner)"))
        }

        var grabbed: [Endpoint] = []
        for endpoint in endpoints {
            let name = "\(endpoint.product) (0x\(String(endpoint.productID, radix: 16)))"
            let tested = endpoint.isTested ? "" : ", untested model"
            do {
                try HIDChannel(endpoint).open()
                findings.append(Finding(level: .ok, message: "\(name) reachable\(tested)", fix: nil))
            } catch ATKError.exclusiveAccess {
                grabbed.append(endpoint)
                let holders = exclusiveHolders(of: endpoint)
                let karabiner = holders.contains { $0.localizedCaseInsensitiveContains("karabiner") }
                findings.append(Finding(
                    level: .fail,
                    message: "\(name) is held exclusively by \(holders.isEmpty ? "another process" : holders.joined(separator: ", "))",
                    fix: karabiner
                        ? "Karabiner-Elements treats it as a keyboard. Run `atkctl doctor --fix-karabiner`, then unplug and replug it."
                        : "quit the app holding it and try again"))
            } catch {
                findings.append(Finding(level: .fail, message: "\(name): \(error)", fix: nil))
            }
        }

        if fixKarabiner, !grabbed.isEmpty {
            findings.append(karabinerIgnore(grabbed))
        }
        guard grabbed.isEmpty else { return findings }

        let session = Session(endpoints: endpoints)
        var mouseVersion: String?
        var receiverVersion: String?
        if session.receiver != nil {
            do {
                receiverVersion = try session.receiverVersion()
                let status = try session.receiverStatus()
                if status.connected {
                    findings.append(Finding(level: .ok, message: "receiver \(receiverVersion!) is connected to the mouse", fix: nil))
                } else if session.mouse == nil {
                    findings.append(Finding(
                        level: .fail,
                        message: "receiver \(receiverVersion!) has no mouse connected (\(status.paired ? "paired, mouse asleep or off" : "not paired"))",
                        fix: status.paired ? "switch the mouse on and move it" : "run `atkctl pair`"))
                }
            } catch {
                findings.append(Finding(level: .warn, message: "receiver: \(error)", fix: nil))
            }
        }
        do {
            mouseVersion = try session.firmwareVersion()
            let battery = try session.battery()
            findings.append(Finding(
                level: battery.percent < 15 && !battery.charging ? .warn : .ok,
                message: "mouse firmware \(mouseVersion!), battery \(battery.percent)%\(battery.charging ? " (charging)" : "")",
                fix: battery.percent < 15 && !battery.charging ? "charge the mouse" : nil))
        } catch {
            if session.mouse != nil || (try? session.receiverStatus().connected) == true {
                findings.append(Finding(level: .warn, message: "mouse: \(error)", fix: nil))
            }
        }
        if let m = mouseVersion, let r = receiverVersion, m.split(separator: ".").first != r.split(separator: ".").first {
            findings.append(Finding(level: .fail, message: "mouse \(m) and receiver \(r) firmware major versions differ",
                                    fix: "update both in ATK Hub; they will not pair across major versions"))
        }
        return findings
    }

    /// The app that turned Secure Input on, if any (loginwindow when the screen is locked).
    static func secureInputOwner() -> String? {
        let output = run("/usr/sbin/ioreg", ["-l", "-w0", "-d1"])
        guard let range = output.range(of: "\"kCGSSessionSecureInputPID\"=") else { return nil }
        let pid = output[range.upperBound...].prefix { $0.isNumber }
        guard !pid.isEmpty else { return nil }
        let name = run("/bin/ps", ["-p", String(pid), "-o", "comm="]).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "pid \(pid)" : name
    }

    private static func run(_ tool: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return "" }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return output
    }

    /// Processes with the device's HID interfaces open, from the IORegistry.
    static func exclusiveHolders(of endpoint: Endpoint) -> [String] {
        let node = "\(endpoint.product)@\(String(endpoint.locationID, radix: 16))"
        let output = run("/usr/sbin/ioreg", ["-l", "-w0", "-r", "-n", node])
        var names: [String] = []
        var inLibClient = false
        for line in output.split(separator: "\n") {
            if line.contains("+-o ") { inLibClient = line.contains("IOHIDLibUserClient") }
            guard inLibClient, let range = line.range(of: "\"IOUserClientCreator\" = \"pid ") else { continue }
            let rest = line[range.upperBound...].dropLast()  // "708, Karabiner-Core-S"
            if let comma = rest.firstIndex(of: ",") {
                let name = rest[rest.index(after: comma)...].trimmingCharacters(in: .whitespaces)
                if !names.contains(name) { names.append(name) }
            }
        }
        return names
    }

    /// Adds an `ignore` rule for each grabbed device to the selected Karabiner profile.
    static func karabinerIgnore(_ endpoints: [Endpoint]) -> Finding {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/karabiner/karabiner.json")
        do {
            let data = try Data(contentsOf: url)
            guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  var profiles = root["profiles"] as? [[String: Any]],
                  let selected = profiles.firstIndex(where: { $0["selected"] as? Bool == true }) ?? profiles.indices.first
            else { return Finding(level: .fail, message: "karabiner.json has no profile to edit", fix: nil) }

            var devices = profiles[selected]["devices"] as? [[String: Any]] ?? []
            var added = 0
            for endpoint in endpoints {
                let identifiers: [String: Any] = ["is_keyboard": true, "product_id": endpoint.productID,
                                                  "vendor_id": Catalog.vendorID]
                let exists = devices.contains { ($0["identifiers"] as? NSDictionary)?.isEqual(to: identifiers) == true }
                if !exists {
                    devices.append(["identifiers": identifiers, "ignore": true])
                    added += 1
                }
            }
            guard added > 0 else {
                return Finding(level: .warn, message: "Karabiner already ignores these devices but still holds them",
                               fix: "restart its daemon: sudo launchctl kickstart -k system/org.pqrs.service.daemon.Karabiner-Core-Service")
            }
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
            try data.write(to: url.appendingPathExtension("bak-atkctl-\(stamp)"))
            profiles[selected]["devices"] = devices
            root["profiles"] = profiles
            let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: url)
            return Finding(level: .ok, message: "added \(added) ignore rule(s) to Karabiner (backup next to karabiner.json)",
                           fix: "unplug and replug the receiver so Karabiner lets go of it")
        } catch {
            return Finding(level: .fail, message: "could not edit karabiner.json: \(error.localizedDescription)", fix: nil)
        }
    }
}
