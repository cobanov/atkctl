import ATKKit
import SwiftUI

/// The dark panel: the active DPI large, stages on a slider, the other settings as tiles.
struct MinimalPanelView: View {
    @ObservedObject var model: MouseModel
    let showClassic: () -> Void

    private var snap: Snapshot { model.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if let problem = model.problem { problemRow(problem) }
            if let config = snap.config {
                hero(config)
                if let table = snap.dpi, table.stages.count > 1 { StageSlider(table: table, select: model.selectStage) }
                tiles(config)
                toggles(config)
            }
            footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(width: 380)
        .foregroundStyle(.white)
        .disabled(model.busy || snap.asleep)
    }

    // MARK: sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "computermouse")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(Theme.dim)
            Text(snap.hasMouse ? snap.mouseName : "No mouse")
                .font(Theme.font(17, .medium))
                .foregroundStyle(Theme.dim)
            if let firmware = snap.mouseFirmware {
                Text(firmware).font(Theme.font(17, .medium))
            }
            Spacer()
            if let battery = snap.battery { BatteryRing(battery: battery) }
        }
    }

    private func problemRow(_ problem: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(Theme.font(14, .medium))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            if model.needsInputMonitoring {
                Button("Open Input Monitoring Settings") { model.openInputMonitoringSettings() }
                    .buttonStyle(PillButtonStyle())
            }
        }
    }

    private func hero(_ config: MouseConfig) -> some View {
        HStack(alignment: .lastTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: snap.dpi?.active.map { "\($0.x)" } ?? "–")
                    .font(Theme.font(68, .semibold))
                    .monospacedDigit()
                Text("dpi").font(Theme.font(24, .medium)).foregroundStyle(Theme.dim)
            }
            .fixedSize()
            Spacer(minLength: 12)
            if let table = snap.dpi, let active = table.active {
                // The stage's LED colour, as the mouse shows it.
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(red: Double(active.color.r) / 255, green: Double(active.color.g) / 255,
                                    blue: Double(active.color.b) / 255))
                        .frame(width: 9, height: 9)
                        .shadow(color: Color(red: Double(active.color.r) / 255, green: Double(active.color.g) / 255,
                                             blue: Double(active.color.b) / 255), radius: 5)
                    Text("Stage \(table.activeIndex + 1) of \(table.stages.count)")
                        .font(Theme.font(15, .medium))
                        .foregroundStyle(Theme.dim)
                }
                .padding(.bottom, 10)
            }
        }
    }

    private func tiles(_ config: MouseConfig) -> some View {
        HStack(spacing: 8) {
            Tile(icon: "dot.radiowaves.left.and.right", title: "Polling",
                 value: config.reportRate.map { "\($0.rawValue) Hz" } ?? "?") {
                ChoiceMenu.show(reportRates, current: config.reportRate, title: { "\($0.rawValue) Hz" }, pick: model.setReportRate)
            }
            Tile(icon: "arrow.up.and.down", title: "Lift-off", value: mm(config.liftOffMillimetres)) {
                ChoiceMenu.show((7...17).map { Double($0) / 10 }, current: config.liftOffMillimetres,
                                title: mm, pick: model.setLiftOff)
            }
            Tile(icon: "moon", title: "Sleep", value: duration(config.sleepSeconds)) {
                ChoiceMenu.show(Session.sleepChoices, current: config.sleepSeconds, title: duration, pick: model.setSleep)
            }
            Tile(icon: "timer", title: "Debounce", value: "\(config.debounceMs) ms") {
                ChoiceMenu.show(Session.debounceChoices, current: config.debounceMs, title: { "\($0) ms" }, pick: model.setDebounce)
            }
        }
    }

    private func toggles(_ config: MouseConfig) -> some View {
        HStack(spacing: 8) {
            ToggleTile(icon: "wave.3.right", title: "Motion sync", isOn: config.motionSync, set: model.setMotionSync)
            ToggleTile(icon: "water.waves", title: "Ripple control", isOn: config.rippleControl, set: model.setRipple)
            ToggleTile(icon: "line.diagonal", title: "Angle snap", isOn: config.angleSnapping, set: model.setAngleSnapping)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: snap.hasMouse && !snap.asleep ? "checkmark.shield" : "moon.zzz")
                .font(.system(size: 15))
            Text(status)
                .font(Theme.font(14, .medium))
                .lineLimit(1)
            Spacer()
            if model.busy { ProgressView().controlSize(.small).tint(.white) }
            Button {
                ChoiceMenu.show([
                    (title: "Refresh", checked: false, run: { model.refresh(rescan: true) }),
                    (title: "Open at Login", checked: model.openAtLogin, run: { model.setOpenAtLogin(!model.openAtLogin) }),
                    (title: "Classic Design", checked: false, run: showClassic),
                    (title: "-", checked: false, run: {}),
                    (title: "Quit ATKBar", checked: false, run: { NSApplication.shared.terminate(nil) }),
                ])
            } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 17)).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.dim)
    }

    // MARK: helpers

    private var status: String {
        if snap.asleep { return "Mouse asleep" }
        if snap.hasMouse {
            return ["Connected", snap.link?.label].compactMap { $0 }.joined(separator: " · ")
        }
        return snap.receiverName == nil ? "No receiver" : "Receiver has no mouse"
    }

    private var reportRates: [ReportRate] {
        let max = snap.link?.maxReportRate ?? .hz8000
        return ReportRate.allCases.filter { $0.rawValue <= max.rawValue || $0 == snap.config?.reportRate }
    }

    private func mm(_ value: Double) -> String { String(format: "%.1f mm", value) }

    private func duration(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
    }
}

// MARK: - pieces

enum Theme {
    static let dim = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.35)
    static let card = Color.white.opacity(0.055)
    static let cardBorder = Color.white.opacity(0.05)

    static func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
}

/// DPI stages on a track: drag or click to pick one, or step with − and +.
struct StageSlider: View {
    let table: DPITable
    let select: (Int) -> Void
    @State private var dragX: CGFloat?

    private var last: Int { table.stages.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                RoundButton(icon: "minus") { if table.activeIndex > 0 { select(table.activeIndex - 1) } }
                    .disabled(table.activeIndex == 0)
                GeometryReader { geo in track(width: geo.size.width) }
                    .frame(height: 50)
                RoundButton(icon: "plus") { if table.activeIndex < last { select(table.activeIndex + 1) } }
                    .disabled(table.activeIndex == last)
            }
            HStack {
                Text(verbatim: "\(table.stages[0].x)")
                Spacer()
                Text(verbatim: "\(table.stages[last].x)")
            }
            .font(Theme.font(14, .medium))
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 62)
        }
    }

    private func track(width: CGFloat) -> some View {
        let knob: CGFloat = 30, inset: CGFloat = 6
        let span = width - knob - inset * 2
        let stageX = { (i: Int) in inset + span * CGFloat(i) / CGFloat(max(last, 1)) }
        let x = dragX ?? stageX(table.activeIndex)
        let nearest = { (x: CGFloat) in Int(((x - inset) / span * CGFloat(last)).rounded()).clamped(0, last) }

        return ZStack(alignment: .leading) {
            Capsule().fill(Color.black)
                .overlay(Capsule().stroke(Theme.cardBorder))
            Capsule()
                .fill(LinearGradient(colors: [Color.white.opacity(0.32), Color.white.opacity(0.1)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: x + knob + inset)
            ForEach(table.stages.indices, id: \.self) { i in
                Circle().fill(Color.white.opacity(i <= nearest(x) ? 0 : 0.25))
                    .frame(width: 4, height: 4)
                    .offset(x: stageX(i) + knob / 2 - 2)
            }
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.88))
                .frame(width: knob, height: 38)
                .shadow(color: .black.opacity(0.5), radius: 6)
                .offset(x: x)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { dragX = ($0.location.x - knob / 2).clamped(inset, inset + span) }
            .onEnded { value in
                let i = nearest((value.location.x - knob / 2).clamped(inset, inset + span))
                withAnimation(.easeOut(duration: 0.15)) { dragX = nil }
                if i != table.activeIndex { select(i) }
            })
        .animation(.easeOut(duration: 0.15), value: table.activeIndex)
    }
}

struct RoundButton: View {
    let icon: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 50, height: 50)
                .background(Circle().fill(Theme.card))
                .overlay(Circle().stroke(Theme.cardBorder))
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// A setting shown as a card; clicking opens its choices.
struct Tile: View {
    let icon: String
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: icon).font(.system(size: 20, weight: .light)).foregroundStyle(Theme.dim)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
                }
                .frame(height: 24)
                Spacer(minLength: 0)
                Text(title).font(Theme.font(13, .medium)).foregroundStyle(Theme.faint)
                Text(verbatim: value).font(Theme.font(17, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 96)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cardBorder))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A card with an icon, a switch and a title; the whole card toggles.
struct ToggleTile: View {
    let icon: String
    let title: String
    let isOn: Bool
    let set: (Bool) -> Void

    var body: some View {
        Button { set(!isOn) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: icon).font(.system(size: 17, weight: .light))
                        .foregroundStyle(isOn ? Color.white : Theme.dim)
                    Spacer(minLength: 4)
                    Switch(isOn: isOn)
                }
                Spacer(minLength: 0)
                Text(title).font(Theme.font(15, .medium)).lineLimit(1)
                    .foregroundStyle(isOn ? Color.white : Theme.dim)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 76)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.cardBorder))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct Switch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.white.opacity(0.9) : Color.white.opacity(0.1))
            .frame(width: 40, height: 24)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Color.black : Color.white.opacity(0.75))
                    .frame(width: 22, height: 18)
                    .padding(3)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

struct BatteryRing: View {
    let battery: Battery

    private var color: Color {
        if battery.charging { return .green }
        return battery.percent <= MouseModel.lowBattery ? .red : .white
    }

    var body: some View {
        ZStack {
            Circle().fill(Theme.card)
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 3).padding(5)
            Circle()
                .trim(from: 0, to: CGFloat(battery.percent) / 100)
                .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(5)
            Text(battery.charging ? "⚡︎" : "\(battery.percent)")
                .font(Theme.font(14, .semibold))
                .monospacedDigit()
        }
        .frame(width: 48, height: 48)
        .help("Battery \(battery.percent)%\(battery.charging ? ", charging" : "")")
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(14, .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.2 : 0.1)))
    }
}

private extension Comparable {
    func clamped(_ low: Self, _ high: Self) -> Self { min(max(self, low), high) }
}
