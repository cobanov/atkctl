import ATKKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: MouseModel
    @ViewState private var liftOff = 1.0

    private var snap: Snapshot { model.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let problem = model.problem { problemView(problem) }
            if let config = snap.config { settings(config) }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { model.refresh() }
        .onChange(of: snap.config?.liftOffMillimetres) { liftOff = $0 ?? liftOff }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(snap.hasMouse ? snap.mouseName : "No mouse").font(.headline)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                if let battery = snap.battery { BatteryBadge(battery: battery) }
            }
            if model.isDemo {
                HStack {
                    Text("Demo: nothing is sent to a mouse").font(.caption).foregroundStyle(.orange)
                    Button("Exit Demo") { model.stopDemo() }.controlSize(.mini)
                }
            }
            if let receiver = snap.receiverName {
                Text([receiver, snap.receiverConnected ? "connected" : "no mouse", snap.link?.label]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let mouse = snap.mouseFirmware {
                Text("Firmware: mouse \(mouse)" + (snap.receiverFirmware.map { ", receiver \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func problemView(_ problem: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            if model.needsInputMonitoring {
                Button("Open Input Monitoring Settings") { model.openInputMonitoringSettings() }
                    .controlSize(.small)
            }
            if !snap.hasMouse {
                Button("Try Demo") { model.startDemo() }.controlSize(.small)
            }
        }
    }

    // MARK: settings

    private func settings(_ config: MouseConfig) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            if let table = snap.dpi, !table.stages.isEmpty {
                GridRow {
                    Text("DPI")
                    Picker("DPI", selection: Binding(get: { table.activeIndex }, set: model.selectStage)) {
                        ForEach(table.stages.indices, id: \.self) { i in
                            Text(dpiLabel(table.stages[i])).tag(i)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
            GridRow {
                Text("Polling")
                Picker("Polling", selection: Binding(get: { config.reportRate ?? .hz1000 }, set: model.setReportRate)) {
                    ForEach(reportRates, id: \.self) { Text("\($0.rawValue) Hz").tag($0) }
                }
                .labelsHidden()
            }
            GridRow {
                Text("Lift-off")
                HStack {
                    Slider(value: $liftOff, in: 0.7...1.7, step: 0.1) { editing in
                        if !editing, abs(liftOff - config.liftOffMillimetres) > 0.01 { model.setLiftOff(liftOff) }
                    }
                    Text(String(format: "%.1f mm", liftOff)).monospacedDigit().frame(width: 52, alignment: .trailing)
                }
            }
            GridRow {
                Text("Sleep")
                Picker("Sleep", selection: Binding(get: { config.sleepSeconds }, set: model.setSleep)) {
                    ForEach(choices(Session.sleepChoices, current: config.sleepSeconds), id: \.self) {
                        Text(duration($0)).tag($0)
                    }
                }
                .labelsHidden()
            }
            GridRow {
                Text("Debounce")
                Picker("Debounce", selection: Binding(get: { config.debounceMs }, set: model.setDebounce)) {
                    ForEach(choices(Session.debounceChoices, current: config.debounceMs), id: \.self) {
                        Text("\($0) ms").tag($0)
                    }
                }
                .labelsHidden()
            }
            Divider().gridCellColumns(2)
            toggle("Motion sync", config.motionSync, model.setMotionSync)
            toggle("Ripple control", config.rippleControl, model.setRipple)
            toggle("Angle snapping", config.angleSnapping, model.setAngleSnapping)
        }
        .disabled(model.busy || snap.asleep)
        .onAppear { liftOff = config.liftOffMillimetres }
    }

    private func toggle(_ title: String, _ value: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        GridRow {
            Text(title)
            Toggle(title, isOn: Binding(get: { value }, set: set))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .gridColumnAlignment(.trailing)
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            Toggle("Open at login", isOn: Binding(get: { model.openAtLogin }, set: model.setOpenAtLogin))
                .toggleStyle(.checkbox)
                .font(.callout)
            Spacer()
            Button { UserDefaults.standard.set(PanelStyle.minimal.rawValue, forKey: PanelStyle.key) } label: {
                Image(systemName: "sparkles")
            }
            .buttonStyle(.borderless)
            .help("Switch to the minimal design")
            Button { model.refresh(rescan: true) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Read the mouse again")
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
    }

    // MARK: helpers

    /// Rates the current link can carry; the current one stays listed even if it is faster.
    private var reportRates: [ReportRate] {
        let max = snap.link?.maxReportRate ?? .hz8000
        let current = snap.config?.reportRate
        return ReportRate.allCases.filter { $0.rawValue <= max.rawValue || $0 == current }
    }

    private func choices(_ values: [Int], current: Int) -> [Int] {
        values.contains(current) ? values : (values + [current]).sorted()
    }

    private func dpiLabel(_ stage: DPIStage) -> String {
        stage.x == stage.y ? "\(stage.x)" : "\(stage.x)×\(stage.y)"
    }

    private func duration(_ seconds: Int) -> String {
        seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
    }
}

struct BatteryBadge: View {
    let battery: Battery

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: battery.charging ? "battery.100.bolt" : symbol)
                .foregroundStyle(battery.percent <= MouseModel.lowBattery && !battery.charging ? .red : .primary)
            Text("\(battery.percent)%").monospacedDigit()
        }
        .font(.callout)
    }

    private var symbol: String {
        switch battery.percent {
        case ..<13: "battery.0"
        case ..<38: "battery.25"
        case ..<63: "battery.50"
        case ..<88: "battery.75"
        default: "battery.100"
        }
    }
}
