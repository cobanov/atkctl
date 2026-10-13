import ATKKit
import SwiftUI

/// The dark panel. The mouse itself is the centrepiece, lit in its active stage's LED colour;
/// that colour is the only one on the panel. Everything else is type on black.
struct MinimalPanelView: View {
    @ObservedObject var model: MouseModel
    @ObservedObject private var images = ProductImages.shared
    @State private var skinRevision = 0
    let showClassic: () -> Void

    private var snap: Snapshot { model.snapshot }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let config = snap.config, let table = snap.dpi {
                hero(table)
                    .padding(.top, 24)
                readout(table)
                    .padding(.top, 16)
                StageRow(table: table, colours: look?.look.ledColours != false, select: model.selectStage)
                    .padding(.top, 8)
                Rectangle().fill(Tone.hairline).frame(height: 1)
                    .padding(.top, 16)
                    .padding(.bottom, 6)
                settings(config)
                    .disabled(model.busy || snap.asleep)
            } else {
                emptyState
            }
            footer
                .padding(.top, 14)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(width: 330)
        .foregroundStyle(Tone.primary)
    }

    // MARK: sections

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(snap.hasMouse ? snap.mouseName : "ATK mouse")
                    .font(Tone.type(15, .medium))
                Text(statusLine)
                    .font(Tone.type(12, .regular))
                    .foregroundStyle(model.problem != nil && snap.hasMouse && !snap.asleep ? Tone.warning : Tone.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            if let battery = snap.battery { BatteryGauge(battery: battery).padding(.top, 2) }
        }
    }

    private func readout(_ table: DPITable) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: table.active.map { "\($0.x)" } ?? "–")
                .font(Tone.type(46, .ultraLight))
                .monospacedDigit()
                .numericTransition()
            Text("DPI")
                .font(Tone.type(13, .regular))
                .foregroundStyle(Tone.secondary)
        }
        .animation(.easeOut(duration: 0.2), value: table.activeIndex)
    }

    private func settings(_ config: MouseConfig) -> some View {
        VStack(spacing: 0) {
            ChoiceRow(title: "Polling rate", value: config.reportRate.map { "\($0.rawValue) Hz" } ?? "Unknown") {
                ChoiceMenu.show(reportRates, current: config.reportRate, title: { "\($0.rawValue) Hz" }, pick: model.setReportRate)
            }
            ChoiceRow(title: "Lift-off distance", value: mm(config.liftOffMillimetres)) {
                ChoiceMenu.show((7...17).map { Double($0) / 10 }, current: config.liftOffMillimetres, title: mm,
                                pick: model.setLiftOff)
            }
            ChoiceRow(title: "Sleep after", value: duration(config.sleepSeconds)) {
                ChoiceMenu.show(Session.sleepChoices, current: config.sleepSeconds, title: duration, pick: model.setSleep)
            }
            ChoiceRow(title: "Debounce time", value: "\(config.debounceMs) ms") {
                ChoiceMenu.show(Session.debounceChoices, current: config.debounceMs, title: { "\($0) ms" },
                                pick: model.setDebounce)
            }
            SwitchRow(title: "Motion sync", isOn: config.motionSync, set: model.setMotionSync)
            SwitchRow(title: "Ripple control", isOn: config.rippleControl, set: model.setRipple)
            SwitchRow(title: "Angle snapping", isOn: config.angleSnapping, set: model.setAngleSnapping)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            MouseRender(led: nil, dim: true)
                .padding(.top, 26)
            Text(model.problem ?? "Looking for the mouse")
                .font(Tone.type(13, .regular))
                .foregroundStyle(Tone.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)
            HStack(spacing: 10) {
                if model.needsInputMonitoring {
                    Button("Allow Input Monitoring") { model.openInputMonitoringSettings() }
                }
                Button("Try the demo") { model.startDemo() }
            }
            .buttonStyle(OutlineButtonStyle())
            .padding(.top, 16)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Text(footnote)
                .font(Tone.type(11.5, .regular))
                .foregroundStyle(Tone.tertiaryText)
            Spacer()
            Button {
                ChoiceMenu.show(colourEntries + [
                    .action("Read the mouse again") { model.refresh(rescan: true) },
                    .action("Open at login", checked: model.openAtLogin) { model.setOpenAtLogin(!model.openAtLogin) },
                    .action("Demo mode", checked: model.isDemo) { model.isDemo ? model.stopDemo() : model.startDemo() },
                    .action("Classic design", showClassic),
                    .separator,
                    .action("Quit ATKBar") { NSApplication.shared.terminate(nil) },
                ])
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Tone.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    // MARK: the mouse

    private var look: (pid: Int, look: ModelLook)? {
        guard let pid = snap.modelPID, let look = ModelLooks.byPID[pid] else { return nil }
        return (pid, look)
    }

    /// ATK's photo of the model in the user's colour once it has loaded, the drawing until then.
    @ViewBuilder private func hero(_ table: DPITable) -> some View {
        let _ = skinRevision
        let tint = look?.look.ledColours == false ? nil : table.active.map(Self.led)
        if let (pid, look) = look, let skin = SkinChoice.current(for: pid, look: look), let photo = images.image(skin.path) {
            ProductPhoto(image: photo, glow: tint, dim: snap.asleep)
        } else {
            MouseRender(led: tint ?? Tone.primary, dim: snap.asleep)
        }
    }

    /// The model's colours, for the settings menu; the mouse cannot say which one it is.
    private var colourEntries: [ChoiceMenu.Entry] {
        guard let (pid, look) = look, look.skins.count > 1 else { return [] }
        let current = SkinChoice.current(for: pid, look: look)?.name
        return [.header("Mouse colour")]
            + look.skins.map { skin in
                .action(skin.name, checked: skin.name == current) {
                    SkinChoice.set(skin.name, for: pid)
                    skinRevision += 1
                }
            }
            + [.separator]
    }

    // MARK: text

    private var statusLine: String {
        if model.isDemo { return "Demo mouse, nothing is sent to a device" }
        if snap.asleep { return "Asleep. Move the mouse to wake it." }
        if snap.hasMouse, let problem = model.problem { return problem }
        guard snap.hasMouse else { return snap.receiverName == nil ? "Not connected" : "Receiver connected, no mouse" }
        switch snap.link {
        case .wired1K, .wired2K, .wired4K, .wired8K: return "Connected by cable"
        default: return "Connected through the receiver"
        }
    }

    private var footnote: String {
        guard let mouse = snap.mouseFirmware else { return "" }
        return "Firmware \(mouse)" + (snap.receiverFirmware.map { ", receiver \($0)" } ?? "")
    }

    private var reportRates: [ReportRate] {
        let max = snap.link?.maxReportRate ?? .hz8000
        return ReportRate.allCases.filter { $0.rawValue <= max.rawValue || $0 == snap.config?.reportRate }
    }

    private func mm(_ value: Double) -> String { String(format: "%.1f mm", value) }

    private func duration(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
    }

    static func led(_ stage: DPIStage) -> Color {
        Color(red: Double(stage.color.r) / 255, green: Double(stage.color.g) / 255, blue: Double(stage.color.b) / 255)
    }
}

// MARK: - tokens

enum Tone {
    static let primary = Color(white: 0.94)
    static let secondary = Color(white: 0.55)
    static let tertiaryText = Color(white: 0.42)
    static let track = Color(white: 0.2)
    static let hairline = Color(white: 0.11)
    static let warning = Color(red: 0.96, green: 0.68, blue: 0.25)

    enum Weight: String {
        case ultraLight = "UltraLight", regular = "Regular", medium = "Medium", demiBold = "DemiBold"
    }

    /// Avenir Next, the geometric sans on every Mac closest to the Gotham of Tesla's interface.
    static func type(_ size: CGFloat, _ weight: Weight) -> Font {
        .custom("AvenirNext-\(weight.rawValue)", fixedSize: size)
    }
}

// MARK: - pieces

/// ATK's top-down product photo, lit from behind so a black shell still reads on black.
struct ProductPhoto: View {
    let image: NSImage
    let glow: Color?
    var dim = false

    var body: some View {
        ZStack {
            Ellipse()
                .fill(RadialGradient(colors: [Color.white.opacity(0.13), .clear], center: .center,
                                     startRadius: 0, endRadius: 92))
                .frame(width: 210, height: 180)
            Ellipse()
                .fill(RadialGradient(colors: [(glow ?? .white).opacity(glow == nil ? 0.08 : 0.22), .clear],
                                     center: .center, startRadius: 0, endRadius: 70))
                .frame(width: 150, height: 22)
                .offset(y: 84)
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 164)
                .shadow(color: .black.opacity(0.8), radius: 10, y: 6)
        }
        .frame(height: 176)
        .opacity(dim ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.25), value: glow)
        .accessibilityHidden(true)
    }
}

/// The mouse from above, drawn rather than photographed, with its DPI LED lit.
struct MouseRender: View {
    let led: Color?
    var dim = false

    static let size = CGSize(width: 64, height: 102)

    var body: some View {
        let w = Self.size.width, h = Self.size.height
        ZStack {
            // Light pooling on the surface under the mouse.
            Ellipse()
                .fill(RadialGradient(colors: [Color.white.opacity(0.09), .clear], center: .center,
                                     startRadius: 0, endRadius: 58))
                .frame(width: 128, height: 18)
                .offset(y: h / 2 + 2)
            Group {
                MouseOutline()
                    .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.06)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                MouseOutline()
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.4), Color.white.opacity(0.04)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
                MouseSeams()
                    .stroke(Color.black, lineWidth: 1.1)
            }
            .frame(width: w, height: h)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.38), Color(white: 0.14)], startPoint: .top, endPoint: .bottom))
                .frame(width: 6, height: 14)
                .offset(y: -h * 0.3)
            if let led {
                Circle()
                    .fill(led)
                    .frame(width: 3.5, height: 3.5)
                    .shadow(color: led, radius: 4)
                    .shadow(color: led.opacity(0.7), radius: 10)
                    .offset(y: -h * 0.175)
            }
        }
        .frame(width: w, height: h)
        .opacity(dim ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.25), value: led)
        .accessibilityHidden(true)
    }
}

/// A symmetric ergonomic shell, widest two thirds of the way back.
struct MouseOutline: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        path.move(to: p(0.5, 0))
        path.addCurve(to: p(1, 0.56), control1: p(0.82, 0), control2: p(0.99, 0.22))
        path.addCurve(to: p(0.5, 1), control1: p(1.01, 0.86), control2: p(0.8, 1))
        path.addCurve(to: p(0, 0.56), control1: p(0.2, 1), control2: p(-0.01, 0.86))
        path.addCurve(to: p(0.5, 0), control1: p(0.01, 0.22), control2: p(0.18, 0))
        return path
    }
}

/// The split between the buttons, interrupted by the wheel, and the buttons' rear edge.
struct MouseSeams: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        path.move(to: p(0.5, 0.005))
        path.addLine(to: p(0.5, 0.12))
        path.move(to: p(0.5, 0.36))
        path.addLine(to: p(0.5, 0.415))
        path.move(to: p(0.07, 0.42))
        path.addQuadCurve(to: p(0.93, 0.42), control: p(0.5, 0.455))
        return path
    }
}

/// DPI stages as a row of numbers; the active one is bright and carries its LED colour below.
struct StageRow: View {
    let table: DPITable
    /// Whether the mouse's light shows the stage colours; a white dot otherwise.
    let colours: Bool
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(table.stages.indices, id: \.self) { i in
                let active = i == table.activeIndex
                Button { if !active { select(i) } } label: {
                    VStack(spacing: 6) {
                        Text(verbatim: "\(table.stages[i].x)")
                            .font(Tone.type(13, active ? .medium : .regular))
                            .foregroundStyle(active ? Tone.primary : Tone.secondary)
                        Circle()
                            .fill(active ? (colours ? MinimalPanelView.led(table.stages[i]) : Tone.primary) : .clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Stage \(i + 1)")
            }
        }
        .animation(.easeOut(duration: 0.2), value: table.activeIndex)
    }
}

/// A setting whose value opens a menu of choices.
struct ChoiceRow: View {
    let title: String
    let value: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(Tone.type(13.5, .regular))
                Spacer()
                Text(verbatim: value).font(Tone.type(13.5, .regular)).foregroundStyle(Tone.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Tone.tertiaryText)
            }
            .rowFrame(hover: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct SwitchRow: View {
    let title: String
    let isOn: Bool
    let set: (Bool) -> Void
    @State private var hover = false

    var body: some View {
        Button { set(!isOn) } label: {
            HStack {
                Text(title).font(Tone.type(13.5, .regular))
                Spacer()
                Capsule()
                    .fill(isOn ? Tone.primary : Tone.track)
                    .frame(width: 32, height: 19)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(isOn ? Color.black : Color(white: 0.58))
                            .frame(width: 15, height: 15)
                            .padding(2)
                    }
                    .animation(.easeOut(duration: 0.15), value: isOn)
            }
            .rowFrame(hover: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct BatteryGauge: View {
    let battery: Battery

    private var fill: Color {
        if battery.charging { return Color(red: 0.35, green: 0.8, blue: 0.45) }
        return battery.percent <= MouseModel.lowBattery ? Color(red: 0.95, green: 0.3, blue: 0.25) : Tone.primary
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: "\(battery.percent)%")
                .font(Tone.type(13, .medium))
                .monospacedDigit()
            HStack(spacing: 1) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .stroke(Tone.secondary, lineWidth: 1)
                    .frame(width: 22, height: 11)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                            .fill(fill)
                            .frame(width: max(1.5, 18 * CGFloat(battery.percent) / 100), height: 7)
                            .padding(.leading, 2)
                    }
                RoundedRectangle(cornerRadius: 0.8).fill(Tone.secondary).frame(width: 1.5, height: 4)
            }
        }
        .help(battery.charging ? "Charging" : "Battery")
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tone.type(12.5, .medium))
            .foregroundStyle(Tone.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
            .contentShape(Capsule())
    }
}

private extension View {
    func rowFrame(hover: Bool) -> some View {
        frame(height: 32)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(hover ? 0.05 : 0)))
            .padding(.horizontal, -8)
            .contentShape(Rectangle())
    }

    @ViewBuilder func numericTransition() -> some View {
        if #available(macOS 14, *) { contentTransition(.numericText()) } else { self }
    }
}
