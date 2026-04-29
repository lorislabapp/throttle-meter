import AppKit
import GRDB
import SwiftUI

struct DropdownView: View {
    @Environment(AppState.self) private var appState

    enum Mode {
        case meter
        case settings(SettingsTab)
        case stats
        case about
    }

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case calibration = "Calibration"
        case hooks = "Hooks"
        case privacy = "Privacy"
    }

    @State private var mode: Mode = .meter

    var body: some View {
        Group {
            if !appState.firstRunDone {
                FirstRunInline()
            } else {
                switch mode {
                case .meter:
                    meterContent
                case .settings(let tab):
                    settingsContent(tab: tab)
                case .stats:
                    StatsInline(onBack: { mode = .meter })
                case .about:
                    AboutInline(onBack: { mode = .settings(.general) })
                }
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    // MARK: - Meter mode

    private var meterContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !appState.claudeCodeDetected {
                emptyState(message: "Claude Code not detected. Install it to start measuring.")
            } else if !appState.snapshot.hasAnyData {
                emptyState(message: "No sessions yet — start one in Claude Code.")
            } else {
                windowsList
            }
            if appState.savedTokensThisWeek > 0 {
                savingsBanner
            }
            Divider().padding(.vertical, 4)
            footer
        }
    }

    /// Hero card showing tokens saved by the token-opt hooks this week.
    private var savingsBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(formatTokens(appState.savedTokensThisWeek))
                        .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Text("tokens saved")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                Text("This week — Throttle's hooks pruning irrelevant context")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.45, blue: 0.27),
                            Color(red: 0.10, green: 0.62, blue: 0.39)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.top, 10)
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.0fk", Double(n) / 1_000) }
        return "\(n)"
    }

    private var header: some View {
        HStack {
            Text("Throttle Meter")
                .font(.headline)
            Spacer()
            if let pct = appState.snapshot.session5h.percentUsed {
                Text("\(Int(pct * 100))%")
                    .font(.headline)
                    .foregroundStyle(headerColor(for: pct))
            }
        }
        .padding(.bottom, 6)
    }

    private func headerColor(for pct: Double) -> Color {
        switch pct {
        case ..<0.5:  return .secondary
        case ..<0.8:  return .primary
        case ..<0.95: return .orange
        default:      return .red
        }
    }

    private func emptyState(message: String) -> some View {
        VStack {
            Image(systemName: "gauge.with.dots.needle.0percent")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private var windowsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            metricRow(window: appState.snapshot.session5h, title: String(localized: "Session (5h)"))
            metricRow(window: appState.snapshot.weeklyAll, title: String(localized: "Weekly all models"))
            metricRow(window: appState.snapshot.weeklySonnet, title: String(localized: "Weekly Sonnet only"))
        }
    }

    @ViewBuilder
    private func metricRow(window: UsageSnapshot.Window, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                if let pct = window.percentUsed {
                    Text("\(Int(pct * 100))% used")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("not calibrated")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            if let pct = window.percentUsed {
                ProgressView(value: pct)
                    .progressViewStyle(.linear)
                    .tint(progressTint(for: pct))
            }
            if window.resetInSeconds > 0 {
                Text("resets in \(formatDuration(window.resetInSeconds)) (\(formatWallClock(window.resetInSeconds)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatWallClock(_ secondsFromNow: Int64) -> String {
        let target = Date().addingTimeInterval(TimeInterval(secondsFromNow))
        let cal = Calendar.current
        let now = Date()
        let f = DateFormatter()
        f.locale = .current
        let isToday = cal.isDateInToday(target)
        let isTomorrow = cal.isDateInTomorrow(target)
        let withinThreeDays = (target.timeIntervalSince(now)) < 3 * 24 * 3600
        if isToday {
            f.setLocalizedDateFormatFromTemplate("ha")
            return f.string(from: target).lowercased()
        }
        if isTomorrow {
            f.setLocalizedDateFormatFromTemplate("ha")
            return "tmrw \(f.string(from: target).lowercased())"
        }
        if withinThreeDays {
            f.setLocalizedDateFormatFromTemplate("EEEha")
            return f.string(from: target).lowercased()
        }
        f.setLocalizedDateFormatFromTemplate("EEEMMMdha")
        return f.string(from: target).lowercased()
    }

    private func progressTint(for pct: Double) -> Color {
        switch pct {
        case ..<0.8:  return .accentColor
        case ..<0.95: return .orange
        default:      return .red
        }
    }

    private func formatDuration(_ seconds: Int64) -> String {
        let s = Int(seconds)
        let h = s / 3600
        let m = (s % 3600) / 60
        if h >= 24 { return "\(h / 24)d \(h % 24)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if let url = URL(string: "https://claude.ai/settings/usage") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open claude.ai/usage", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.plain)

            Button {
                mode = .stats
            } label: {
                Label("Stats…", systemImage: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.plain)

            Button {
                mode = .settings(.general)
            } label: {
                Label("Settings…", systemImage: "gear")
            }
            .buttonStyle(.plain)

            Button {
                mode = .about
            } label: {
                Label("About Throttle Meter", systemImage: "info.circle")
            }
            .buttonStyle(.plain)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Throttle Meter", systemImage: "power")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
        }
    }

    // MARK: - Settings mode

    private func settingsContent(tab: SettingsTab) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    mode = .meter
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("Settings").font(.headline)
                Spacer()
                Spacer().frame(width: 56)
            }

            Picker("", selection: Binding(
                get: { tab },
                set: { mode = .settings($0) }
            )) {
                ForEach(SettingsTab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider()

            ScrollView {
                Group {
                    switch tab {
                    case .general:     InlineGeneralPane()
                    case .calibration: InlineCalibrationPane()
                    case .hooks:       InlineHooksPane()
                    case .privacy:     InlinePrivacyPane()
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 180, maxHeight: 320)
        }
    }
}

// MARK: - First-run inline view

private struct FirstRunInline: View {
    @Environment(AppState.self) private var appState

    enum PlanChoice: String, CaseIterable, Identifiable {
        case pro = "Pro"
        case max5x = "Max 5×"
        case max20x = "Max 20×"
        case skip = "Skip — auto-calibrate"
        var id: String { rawValue }
    }

    @State private var planChoice: PlanChoice = .skip
    @State private var enableLoginItems: Bool = false
    @State private var step: Int = 0

    private let totalSteps = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            stepIndicator
            Group {
                switch step {
                case 0: stepWelcome
                case 1: stepPlan
                default: stepFinish
                }
            }
            .frame(minHeight: 180, alignment: .top)
            stepNav
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: i == step ? 18 : 6, height: 6)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
            Spacer()
            Text("Step \(step + 1) of \(totalSteps)")
                .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
        }
    }

    private var stepWelcome: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 36)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Throttle Meter").font(.headline)
                    Text("The accurate Claude Code meter for your menu bar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Throttle Meter reads `~/.claude/projects/` locally to compute your session-5h, weekly-all, and weekly-Sonnet usage. Nothing leaves your Mac.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stepPlan: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick your plan").font(.headline)
            Text("So we can pre-fill realistic caps. You can recalibrate exactly later.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Plan", selection: $planChoice) {
                ForEach(PlanChoice.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.radioGroup).labelsHidden()
        }
    }

    private var stepFinish: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Almost done").font(.headline)
            Toggle("Launch Throttle Meter at login", isOn: $enableLoginItems).font(.subheadline)
            Text("Everything is configurable later in Settings.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var stepNav: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.borderless)
            }
            Spacer()
            if step < totalSteps - 1 {
                Button("Next") { step += 1 }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Get Started") { apply() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func apply() {
        if enableLoginItems { try? LoginItemService.setEnabled(true) }
        let preset: [(WindowKind, Int)]? = {
            switch planChoice {
            case .pro:    return [(.session5h, 4_000_000), (.weeklyAll, 60_000_000), (.weeklySonnet, 60_000_000)]
            case .max5x:  return [(.session5h, 8_000_000), (.weeklyAll, 200_000_000), (.weeklySonnet, 200_000_000)]
            case .max20x: return [(.session5h, 20_000_000), (.weeklyAll, 800_000_000), (.weeklySonnet, 800_000_000)]
            case .skip:   return nil
            }
        }()
        if let preset,
           let url = try? DatabaseManager.databaseURL(),
           let pool = try? DatabasePool(path: url.path) {
            try? pool.write { db in
                for (kind, cap) in preset {
                    try CalibrationEngine.setManual(in: db, kind: kind, capTokens: cap)
                }
            }
        }
        appState.markFirstRunDone()
        appState.refresh()
    }
}

// MARK: - Inline Settings panes

private struct InlineGeneralPane: View {
    @Environment(AppState.self) private var appState
    @State private var loginItemsEnabled: Bool = LoginItemService.isEnabled
    @State private var notificationsOn: Bool = ThresholdNotifier.shared.isEnabled
    @State private var calendarStatus: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Startup").font(.subheadline.bold())
            Toggle("Launch Throttle Meter at login", isOn: $loginItemsEnabled)
                .onChange(of: loginItemsEnabled) { _, new in
                    try? LoginItemService.setEnabled(new)
                }

            Divider()

            Text("Notifications").font(.subheadline.bold())
            Toggle("Notify when usage crosses 80% / 95%", isOn: $notificationsOn)
                .onChange(of: notificationsOn) { _, new in
                    ThresholdNotifier.shared.setEnabled(new)
                }
            Text("Triggers a banner on each window the first time it crosses each threshold (debounced 6h).")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add weekly reset reminder to Calendar") {
                Task {
                    let result = await CalendarReminderService.addNextWeeklyReset(in: appState.snapshot)
                    await MainActor.run { handleCalendarResult(result) }
                }
            }
            .buttonStyle(.borderless).controlSize(.small)
            if !calendarStatus.isEmpty {
                Text(calendarStatus).font(.caption2).foregroundStyle(.tertiary)
            }

            Divider()
            HStack {
                Text("Updates").font(.subheadline.bold())
                Spacer()
                Text("Throttle Meter \(currentVersionLabel)")
                    .font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
            Text("Updates ship via GitHub releases. Check github.com/lorislabapp/throttle-meter for new versions.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var currentVersionLabel: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(v) (\(b))"
    }

    private func handleCalendarResult(_ result: CalendarReminderService.Result) {
        switch result {
        case .added:        calendarStatus = "✓ Event added to your default calendar."
        case .denied:       calendarStatus = "Calendar access denied — enable in System Settings."
        case .noResetTime:  calendarStatus = "No reset time available yet — keep using Claude Code."
        case .error(let m): calendarStatus = "Error: \(m)"
        }
    }
}

private struct InlineCalibrationPane: View {
    @Environment(AppState.self) private var appState
    @State private var caps: [WindowKind: Int] = [:]
    @State private var recalPct: [WindowKind: Int] = [
        .session5h: 50, .weeklyAll: 50, .weeklySonnet: 50
    ]

    private static let presets: [WindowKind: [(label: String, tokens: Int)]] = [
        .session5h: [
            ("4M (Pro)",   4_000_000),
            ("8M (Max 5×)", 8_000_000),
            ("20M (Max 20×)", 20_000_000)
        ],
        .weeklyAll: [
            ("60M (Pro)",   60_000_000),
            ("200M (Max 5×)", 200_000_000),
            ("800M (Max 20×)", 800_000_000)
        ],
        .weeklySonnet: [
            ("60M (Pro)",   60_000_000),
            ("200M (Max 5×)", 200_000_000),
            ("800M (Max 20×)", 800_000_000)
        ]
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Caps (tokens)").font(.subheadline.bold())
            row(.session5h,    String(localized: "Session (5h)"))
            row(.weeklyAll,    String(localized: "Weekly all models"))
            row(.weeklySonnet, String(localized: "Weekly Sonnet only"))

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Recalibrate from claude.ai")
                    .font(.subheadline.bold())
                Text("Open claude.ai, read the % shown for each limit, enter it here, then Apply. Throttle Meter adjusts each cap so the meter matches.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            recalRow(.session5h,    String(localized: "Session (5h)"))
            recalRow(.weeklyAll,    String(localized: "Weekly all models"))
            recalRow(.weeklySonnet, String(localized: "Weekly Sonnet only"))

            Divider()
            Button("Reset all calibrations", role: .destructive) {
                resetAll()
            }
            .buttonStyle(.borderless)
        }
        .task { await loadCurrent() }
    }

    @ViewBuilder
    private func recalRow(_ kind: WindowKind, _ label: String) -> some View {
        let used = window(for: kind)?.usedTokens ?? 0
        let pct = recalPct[kind] ?? 50
        let canApply = used > 0 && pct > 0 && pct <= 100
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.bold())
            HStack(spacing: 8) {
                Button { adjustPct(kind, by: -5) } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)

                Button { adjustPct(kind, by: -1) } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)

                Text("\(pct)%")
                    .font(.caption.monospaced())
                    .frame(minWidth: 36, alignment: .center)

                Button { adjustPct(kind, by: 1) } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)

                Button { adjustPct(kind, by: 5) } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Apply") {
                    applyRecalibration(kind: kind)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canApply)
            }
        }
    }

    private func adjustPct(_ kind: WindowKind, by delta: Int) {
        let current = recalPct[kind] ?? 50
        recalPct[kind] = min(100, max(1, current + delta))
    }

    private func window(for kind: WindowKind) -> UsageSnapshot.Window? {
        switch kind {
        case .session5h:    return appState.snapshot.session5h
        case .weeklyAll:    return appState.snapshot.weeklyAll
        case .weeklySonnet: return appState.snapshot.weeklySonnet
        }
    }

    private func applyRecalibration(kind: WindowKind) {
        guard let used = window(for: kind)?.usedTokens, used > 0,
              let pct = recalPct[kind], pct > 0 else { return }
        let newCap = max(1, (used * 100) / pct)
        let rounded = ((newCap + 500) / 1000) * 1000
        save(kind: kind, capTokens: rounded)
    }

    @ViewBuilder
    private func row(_ kind: WindowKind, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption.bold())
                Spacer()
                Text(formatTokens(caps[kind] ?? 0))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(Self.presets[kind] ?? [], id: \.tokens) { preset in
                    Button(preset.label) {
                        save(kind: kind, capTokens: preset.tokens)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n == 0 { return "—" }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func loadCurrent() async {
        guard let url = try? DatabaseManager.databaseURL(),
              let pool = try? DatabasePool(path: url.path) else { return }
        let loaded: [WindowKind: Int] = (try? await Task.detached {
            try pool.read { db in
                var result: [WindowKind: Int] = [:]
                for kind in WindowKind.allCases {
                    result[kind] = try DatabaseQueries.calibration(in: db, kind: kind)?.capTokens ?? 0
                }
                return result
            }
        }.value) ?? [:]
        await MainActor.run { caps = loaded }
    }

    private func save(kind: WindowKind, capTokens: Int) {
        guard let url = try? DatabaseManager.databaseURL(),
              let pool = try? DatabasePool(path: url.path) else { return }
        try? pool.write { db in
            try CalibrationEngine.setManual(in: db, kind: kind, capTokens: capTokens)
        }
        caps[kind] = capTokens
        appState.refresh()
    }

    private func resetAll() {
        guard let url = try? DatabaseManager.databaseURL(),
              let pool = try? DatabasePool(path: url.path) else { return }
        try? pool.write { db in
            for kind in WindowKind.allCases {
                try CalibrationEngine.reset(in: db, kind: kind)
            }
        }
        for kind in WindowKind.allCases { caps[kind] = 0 }
        appState.refresh()
    }
}

private struct InlineHooksPane: View {
    @State private var status = HookStatusService.currentStatus()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(String(localized: "SessionStart router"), ok: status.sessionStartRouterInstalled)
            row(String(localized: "PreCompact extractor"), ok: status.preCompactExtractorInstalled)
            if status.killSwitchSet {
                Text("⚠ Kill switch active — CLAUDE_DISABLE_TOKOPT_HOOKS=1 set in your shell")
                    .font(.caption).foregroundStyle(.orange)
            }
            Divider()
            Text("To install or update the hook scripts, see the README in the repo. To disable, run:")
                .font(.caption).foregroundStyle(.secondary)
            Text("export CLAUDE_DISABLE_TOKOPT_HOOKS=1")
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .task {
            while !Task.isCancelled {
                status = HookStatusService.currentStatus()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func row(_ label: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? .green : .secondary)
            Text(label).font(.subheadline)
            Spacer()
            Text(ok ? "Active" : "Not installed")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct InlinePrivacyPane: View {
    @State private var exportStatus: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local logs").font(.subheadline.bold())
            Button("Reveal log file in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([AppLogger.logFileURL])
            }
            .buttonStyle(.borderless)
            Text("Logs include app behaviour only — no session content.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            Text("Diagnostics").font(.subheadline.bold())
            Text("Bundle anonymized stats (event counts, hook status) into a .zip on your Desktop. No usage content, no model details — token totals only.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Export diagnostics to Desktop") {
                exportStatus = "Building…"
                Task { @MainActor in
                    if let url = await runDiagnosticsExport() {
                        exportStatus = "Saved: \(url.lastPathComponent)"
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        exportStatus = "Failed — see log."
                    }
                }
            }
            .buttonStyle(.bordered).controlSize(.small)
            if !exportStatus.isEmpty {
                Text(exportStatus).font(.caption2).foregroundStyle(.tertiary)
            }

            Divider()
            Text("Telemetry").font(.subheadline.bold())
            Text("Throttle Meter does not collect telemetry.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func runDiagnosticsExport() async -> URL? {
        guard let url = try? DatabaseManager.databaseURL(),
              let pool = try? DatabasePool(path: url.path) else { return nil }
        return DiagnosticsExporter.exportToDesktop(database: pool)
    }
}

// MARK: - About inline

private struct AboutInline: View {
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { onBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                Text("About").font(.headline)
                Spacer()
                Spacer().frame(width: 56)
            }
            Divider()

            VStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Throttle Meter").font(.title2)
                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Built by LorisLabs.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("github.com/lorislabapp/throttle-meter",
                     destination: URL(string: "https://github.com/lorislabapp/throttle-meter")!)
                    .font(.caption)
                Text("MIT License — see LICENSE in the repo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
