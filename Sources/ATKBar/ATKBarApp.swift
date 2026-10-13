import AppKit
import Combine
import SwiftUI

/// Menu bar companion to atkctl: battery in the menu bar, the common settings one click away.
/// Two looks: the minimal dark panel (our own status item and `StatusPanel`) and the classic
/// MenuBarExtra panel. Only one of the two status items is shown at a time.
@main
struct ATKBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = MouseModel.shared
    @AppStorage(PanelStyle.key) private var style = PanelStyle.minimal

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(get: { style == .classic }, set: { _ in })) {
            PanelView(model: model)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: model.menuIcon)
                if !model.menuTitle.isEmpty { Text(model.menuTitle) }
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: StatusPanel?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement does this in the app bundle; this covers `swift run ATKBar`.
        NSApp.setActivationPolicy(.accessory)
        if let path = Preview.requested { return Preview.render(to: path) }
        let model = MouseModel.shared
        let panel = StatusPanel {
            MinimalPanelView(model: model) {
                UserDefaults.standard.set(PanelStyle.classic.rawValue, forKey: PanelStyle.key)
            }
        }
        self.panel = panel
        panel.onOpen = { model.refresh() }
        panel.statusItem.button?.imagePosition = .imageLeading

        model.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.update() } }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in self?.update() }
            .store(in: &subscriptions)
        update()
    }

    private func update() {
        guard let panel else { return }
        let model = MouseModel.shared
        let minimal = PanelStyle(rawValue: UserDefaults.standard.string(forKey: PanelStyle.key) ?? "") != .classic
        if !minimal { panel.close() }
        // Writing isVisible touches UserDefaults, which calls update() again; only write on a change.
        if panel.statusItem.isVisible != minimal { panel.statusItem.isVisible = minimal }
        guard let button = panel.statusItem.button else { return }
        let image = NSImage(systemSymbolName: model.menuIcon, accessibilityDescription: "Mouse")
        image?.isTemplate = true
        button.image = image
        button.title = model.menuTitle.isEmpty ? "" : " \(model.menuTitle)"
        panel.contentChanged()
    }
}
