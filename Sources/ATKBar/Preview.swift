import AppKit
import ATKKit
import SwiftUI

/// `ATKBar --render-preview out.png` draws the minimal panel with the demo mouse and exits.
/// Used for the README and to check the design without a mouse or a screen.
@MainActor
enum Preview {
    static var requested: String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-preview"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static let snapshot = DemoMouse().snapshot

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
