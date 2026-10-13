import AppKit
import ATKKit
import SwiftUI

/// `ATKBar --render-preview out.png` draws the minimal panel with values recorded from an
/// A9 Plus NK and exits. Used for the README and to check the design without a mouse.
@MainActor
enum Preview {
    static var requested: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-preview"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static let snapshot: Snapshot = {
        var snap = Snapshot()
        snap.receiverName = "NK mouse NANO dongle"
        snap.receiverFirmware = "1.0.19"
        snap.receiverConnected = true
        snap.mouseName = "ATK A9 Plus"
        snap.mouseFirmware = "1.0.14"
        snap.battery = Battery(percent: 86, charging: false)
        snap.link = .receiver1K
        snap.config = MouseConfig(Reply(report: [0x08, 0x72, 0x00, 0x15, 0x00, 0x09, 0x11,
                                                 0x00, 0x00, 0x00, 0x01, 0x00, 0x05, 0x01, 0x00, 0x00, 0x78, 0x00, 0x04])!)
        let stages: [UInt8] = [
            0x02, 0x08, 0x90, 0x01, 0x90, 0x01, 0x00, 0x00, 0xFF, 0x00,
            0x20, 0x03, 0x20, 0x03, 0x00, 0xFF, 0x00, 0x00, 0x40, 0x06,
            0x40, 0x06, 0xFF, 0x00, 0x00, 0x00, 0x80, 0x0C, 0x80, 0x0C,
            0xFF, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
        snap.dpi = DPITable(stages + [UInt8](repeating: 0, count: 30))
        return snap
    }()

    static func render(to path: String) {
        let position = ArrowPosition()
        let content = MinimalPanelView(model: MouseModel(preview: snapshot), showClassic: {})
        let view = NSHostingView(rootView: ArrowPanelContainer(position: position, style: ArrowPanelStyle(),
                                                               content: AnyView(content)))
        let size = view.fittingSize
        position.x = size.width - 120  // as if the menu bar item sat right of centre
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = view
        DispatchQueue.main.async {
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            do {
                try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("\(error)\n".utf8))
                exit(1)
            }
        }
    }
}
