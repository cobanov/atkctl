import Foundation
import Darwin

/// Per-user LaunchAgent: a stable copy survives `swift package clean` and repo moves.
enum BatteryService {
    static let label = "dev.cobanov.atkctl.battery"
    static var domain: String { "gui/\(getuid())" }
    static var target: String { "\(domain)/\(label)" }
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static var plist: URL { home.appendingPathComponent("Library/LaunchAgents/\(label).plist") }
    static var binary: URL { home.appendingPathComponent("Library/Application Support/atkctl/atkctl") }
    static var log: URL { home.appendingPathComponent("Library/Logs/atkctl-battery.log") }

    static func install() throws {
        try requireUser()
        guard let executable = Bundle.main.executableURL else {
            throw serviceError("cannot locate the running atkctl executable")
        }
        // Read before stopping the old service, including when invoked from the installed copy.
        let executableData = try Data(contentsOf: executable)
        let fm = FileManager.default
        for directory in [plist.deletingLastPathComponent(), binary.deletingLastPathComponent(), log.deletingLastPathComponent()] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let definition: [String: Any] = [
            "Label": label,
            "ProgramArguments": [binary.path, "--battery-widget"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 10,
            "ProcessType": "Background",
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": log.path,
            "StandardErrorPath": log.path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: definition, format: .xml, options: 0)
        try unloadIfLoaded()
        try executableData.write(to: binary, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        try data.write(to: plist, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plist.path)
        try checked(["enable", target])
        try checked(["bootstrap", domain, plist.path])
        print("Installed and started \(label). It will run at login.")
        print("""

        Input Monitoring permission is required for the service to read the mouse.
        The receiver exposes a keyboard-class HID interface; atkctl reads its vendor
        reports for battery/configuration, not keyboard keystrokes.

        1. Open System Settings > Privacy & Security > Input Monitoring.
        2. Click +, then press Command-Shift-G and enter this exact installed path:
           \(binary.path)
        3. Add atkctl and turn its switch on. Authorizing your terminal or a copy
           in the build directory does not authorize this background service.
        4. After granting permission, restart the service without reinstalling:
           launchctl kickstart -k \(target)

        After updating an ad-hoc-signed build, an existing enabled switch may refer
        to the old binary. If the log still reports denied access, remove atkctl
        from Input Monitoring, add the installed path again, then run step 4.

        Service startup alone does not confirm HID access or battery publication.
        Wake the mouse and check the log for its battery percentage:
        \(log.path)
        """)
        print("Remove with: atkctl --uninstall-service")
    }

    static func uninstall() throws {
        try requireUser()
        try unloadIfLoaded()
        for file in [plist, binary] where FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        print("Stopped and removed \(label). Log retained at \(log.path).")
    }

    private static func requireUser() throws {
        guard getuid() != 0 else { throw serviceError("run this as your logged-in user, without sudo") }
        // Fail before changing files when no GUI login session is available.
        try checked(["print", domain])
    }

    private static func unloadIfLoaded() throws {
        if try launchctl(["print", target]).status == 0 {
            try checked(["bootout", target])
            // bootout returns before the process has finished its SIGTERM cleanup.
            let deadline = Date().addingTimeInterval(8)
            while try launchctl(["print", target]).status == 0 {
                guard Date() < deadline else {
                    throw serviceError("timed out waiting for the old battery service to stop")
                }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }

    private static func checked(_ arguments: [String]) throws {
        let result = try launchctl(arguments)
        guard result.status == 0 else {
            throw serviceError("launchctl \(arguments.joined(separator: " ")) failed (\(result.status)): \(result.output)")
        }
    }

    private static func launchctl(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func serviceError(_ message: String) -> NSError {
        NSError(domain: label, code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
