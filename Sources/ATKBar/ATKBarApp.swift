import AppKit
import SwiftUI

/// Menu bar companion to atkctl: battery in the menu bar, the common settings one click away.
@main
struct ATKBarApp: App {
    @StateObject private var model = MouseModel()

    init() {
        // LSUIElement does this in the app bundle; this covers `swift run ATKBar`.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
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
