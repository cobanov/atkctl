import AppKit
import ATKKit
import IOKit.hid
import ServiceManagement
import UserNotifications

@MainActor
final class MouseModel: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var problem: String?
    @Published private(set) var needsInputMonitoring = false
    @Published private(set) var busy = false
    @Published private(set) var openAtLogin = false

    static let lowBattery = 15
    private let device = DeviceThread()
    private let backend = Backend()
    private var hotPlug: HotPlug?
    private var timer: Timer?
    private var pendingRescan: DispatchWorkItem?
    private var warnedLow = false
    private let bundled = Bundle.main.bundleIdentifier != nil

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
        snapshot.hasMouse ? "computermouse.fill" : "computermouse"
    }

    // MARK: reading

    func refresh(rescan: Bool = false) {
        run { try $0.read(rescan: rescan) }
    }

    private func scheduleRescan() {
        pendingRescan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh(rescan: true) }
        pendingRescan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func run(_ job: @escaping (Backend) throws -> Snapshot) {
        busy = true
        let backend = backend
        device.perform {
            let result = Result { try job(backend) }
            DispatchQueue.main.async { self.finish(result) }
        }
    }

    private func finish(_ result: Result<Snapshot, Error>) {
        busy = false
        switch result {
        case .success(let snap):
            snapshot = snap
            problem = snap.receiverName != nil && !snap.receiverConnected
                ? "The receiver has no mouse. Switch the mouse on and move it, or run atkctl pair in a terminal."
                : nil
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
        run { try $0.apply(change) }
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
