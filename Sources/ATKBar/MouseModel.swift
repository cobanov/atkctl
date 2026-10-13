import AppKit
import ATKKit
import IOKit.hid
import ServiceManagement
import UserNotifications

/// Which panel the menu bar item opens.
enum PanelStyle: String {
    case minimal, classic
    static let key = "panelStyle"
}

@MainActor
final class MouseModel: ObservableObject {
    static let shared = MouseModel()

    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var problem: String?
    @Published private(set) var needsInputMonitoring = false
    /// A setting is being written; controls wait for it. Background reads do not set this.
    @Published private(set) var busy = false
    private var pendingWrites = 0
    private var isPreview = false
    @Published private(set) var openAtLogin = false

    static let lowBattery = 15
    private let device = DeviceThread()
    private let backend = Backend()
    private var hotPlug: HotPlug?
    private var timer: Timer?
    private var pendingRescan: DispatchWorkItem?
    private var warnedLow = false
    private let bundled = Bundle.main.bundleIdentifier != nil

    /// Shows `snapshot` and never touches the hardware; for `--render-preview`.
    init(preview snapshot: Snapshot) {
        self.snapshot = snapshot
        isPreview = true
    }

    init() {
        if bundled {
            openAtLogin = SMAppService.mainApp.status == .enabled
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        checkInputMonitoring()
        hotPlug = HotPlug { [weak self] in Task { @MainActor in self?.scheduleRescan() } }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.scheduleRescan() } }
        refresh(rescan: true)
    }

    // MARK: menu bar

    var menuTitle: String {
        guard let battery = snapshot.battery else { return "" }
        return "\(battery.percent)%"
    }

    var menuIcon: String {
        snapshot.hasMouse && !snapshot.asleep ? "computermouse.fill" : "computermouse"
    }

    // MARK: reading

    func refresh(rescan: Bool = false) {
        run(write: false) { try $0.read(rescan: rescan) }
    }

    private func scheduleRescan() {
        pendingRescan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh(rescan: true) }
        pendingRescan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func run(write: Bool, _ job: @escaping (Backend) throws -> Snapshot) {
        guard !isPreview else { return }
        if write { pendingWrites += 1; busy = true }
        let backend = backend
        device.perform {
            let result = Result { try job(backend) }
            DispatchQueue.main.async {
                if write { self.pendingWrites -= 1; self.busy = self.pendingWrites > 0 }
                self.finish(result)
            }
        }
    }

    private func finish(_ result: Result<Snapshot, Error>) {
        switch result {
        case .success(var snap):
            if !snap.hasMouse, snap.receiverName != nil, snapshot.hasMouse {
                // The mouse is asleep: keep what it said last.
                snap.mouseName = snapshot.mouseName
                snap.mouseFirmware = snapshot.mouseFirmware
                snap.battery = snapshot.battery
                snap.link = snapshot.link
                snap.config = snapshot.config
                snap.dpi = snapshot.dpi
                snap.asleep = true
            }
            snapshot = snap
            if snap.receiverName != nil && !snap.receiverConnected {
                // The receiver cannot tell an asleep mouse from a forgotten one.
                problem = "No mouse connected. Move the mouse to wake it; if it stays off, pair it with atkctl pair."
            } else {
                problem = nil
            }
            needsInputMonitoring = false
            watchBattery()
        case .failure(ATKError.secureInput):
            problem = "Screen is locked or a password field is focused; macOS blocks the receiver until then."
        case .failure(ATKError.inputMonitoring):
            needsInputMonitoring = true
            problem = "ATKBar needs Input Monitoring to talk to the receiver."
        case .failure(ATKError.notConnected(let message)):
            snapshot = Snapshot()
            problem = message
        case .failure(let error):
            problem = "\(error)".prefix(1).uppercased() + "\(error)".dropFirst()
        }
    }

    // MARK: settings

    func apply(_ change: @escaping (Session) throws -> Void) {
        run(write: true) { try $0.apply(change) }
    }

    func selectStage(_ index: Int) { apply { try $0.selectDPIStage(index) } }
    func setReportRate(_ rate: ReportRate) { apply { try $0.setReportRate(rate) } }
    func setLiftOff(_ millimetres: Double) { apply { try $0.setLiftOff(millimetres: millimetres) } }
    func setSleep(_ seconds: Int) { apply { try $0.setSleep(seconds: seconds) } }
    func setDebounce(_ ms: Int) { apply { try $0.setDebounce(ms: ms) } }
    func setMotionSync(_ on: Bool) { apply { try $0.setMotionSync(on) } }
    func setRipple(_ on: Bool) { apply { try $0.setRippleControl(on) } }
    func setAngleSnapping(_ on: Bool) { apply { try $0.setAngleSnapping(on) } }

    // MARK: app

    func setOpenAtLogin(_ on: Bool) {
        guard bundled else { return }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            problem = "Could not change the login item: \(error.localizedDescription)"
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    func openInputMonitoringSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    private func checkInputMonitoring() {
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            // Shows the system prompt the first time; afterwards it only answers.
            needsInputMonitoring = !IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    private func watchBattery() {
        guard let battery = snapshot.battery else { return }
        if battery.charging || battery.percent > Self.lowBattery + 5 { warnedLow = false }
        guard bundled, !warnedLow, !battery.charging, battery.percent <= Self.lowBattery else { return }
        warnedLow = true
        let content = UNMutableNotificationContent()
        content.title = "\(snapshot.mouseName) battery at \(battery.percent)%"
        content.body = "Plug in the cable to charge it."
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "low-battery", content: content, trigger: nil))
    }
}
