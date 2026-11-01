import AppKit
import Charts
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer().frame(maxWidth: .infinity)
                Picker("页面", selection: $model.dashboardTab) {
                    Text("概览").tag(DashboardTab.overview)
                    Text("历史").tag(DashboardTab.history)
                    Text("设置").tag(DashboardTab.settings)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 228)
                HStack(spacing: 10) {
                    Spacer()
                    if model.isRefreshing {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    }
                    Button(action: model.refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless).disabled(model.isRefreshing)
                    .accessibilityLabel("刷新用量").help("刷新用量 ⌘R")
                    .keyboardShortcut("r", modifiers: .command)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            Group {
                switch model.dashboardTab {
                case .overview: OverviewView(model: model)
                case .history: HistoryView(model: model)
                case .settings: SettingsView(model: model, settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 5, height: 5)
                Text(statusText).lineLimit(1).help(model.refreshText)
                Spacer()
                if let bucket = model.selectedBucket {
                    Text("\(bucket.displayName) · \(bucket.planName)")
                        .lineLimit(1)
                }
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .frame(minWidth: 720, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusColor: Color {
        if model.lastError != nil { return .orange }
        return model.dataIsStale ? .secondary : .green
    }

    private var statusText: String {
        if model.isRefreshing { return "正在更新…" }
        if model.lastError != nil { return model.snapshot == nil ? "读取失败 · 点击刷新重试" : "更新失败 · 显示缓存" }
        guard let snapshot = model.snapshot else { return "等待数据" }
        if model.dataIsStale { return "缓存数据 · \(DisplayFormat.dateTime.string(from: snapshot.fetchedAt))" }
        return "更新于 \(DisplayFormat.dateTime.string(from: snapshot.fetchedAt))"
    }
}

struct OverviewView: View {
    @ObservedObject var model: AppModel

    private var window: RateLimitWindow? { model.selectedWindow }
    private var remaining: Double? { window?.usedPercent.map { max(0, min(100, 100 - $0)) } }
    private var isCurrent: Bool { model.lastError == nil && !model.dataIsStale }
    private var tint: Color {
        guard isCurrent else { return .secondary }
        if model.risk == .critical { return .red }
        if model.risk == .watch { return .orange }
        return .accentColor
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                quotaSummary
                Divider()
                HistoryChart(
                    points: UsageStatistics.dayPoints(buckets: model.snapshot?.usage.dailyUsageBuckets ?? [], days: 30),
                    title: "近 30 日用量", height: 145
                )
                Divider()
                HStack(spacing: 20) {
                    DashboardMetric(title: "累计 token", value: DisplayFormat.tokens(model.summary?.lifetimeTokens))
                    DashboardMetric(title: "单日峰值", value: DisplayFormat.tokens(model.summary?.peakDailyTokens))
                    DashboardMetric(title: "最长任务", value: model.summary?.longestRunningTurnSec.map(duration) ?? "—")
                    DashboardMetric(title: "连续使用", value: model.summary?.currentStreakDays.map { "\($0) 天" } ?? "—")
                }
                .help(model.insight)
            }
            .padding(22)
        }
    }

    private var quotaSummary: some View {
        HStack(alignment: .center, spacing: 30) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if model.buckets.count > 1 {
                        Picker("配额", selection: Binding(
                            get: { model.selectedBucket?.id ?? "" }, set: model.selectBucket
                        )) {
                            ForEach(model.buckets) { Text($0.displayName).tag($0.id) }
                        }
                        .labelsHidden().pickerStyle(.menu).lineLimit(1)
                        .frame(maxWidth: 180)
                    } else {
                        Text(model.selectedBucket?.displayName ?? "当前配额")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(cycleName(window)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(remaining.map { String(Int($0.rounded())) } ?? "—")
                        .font(.system(size: 52, weight: .medium, design: .rounded)).monospacedDigit()
                    if remaining != nil {
                        Text("%").font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
                    }
                    Text("剩余").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ProgressView(value: remaining ?? 0, total: 100)
                    .tint(tint).frame(maxWidth: 280)
                    .accessibilityLabel("剩余配额")
                    .accessibilityValue(DisplayFormat.percent(remaining))
                HStack {
                    Text("已用 \(DisplayFormat.percent(window?.usedPercent))")
                    Spacer()
                    if isCurrent, remaining != nil, model.risk != .unknown {
                        Text(remaining == 0 ? "已用尽" : model.risk.title).foregroundStyle(tint)
                    }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: 280)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 17) {
                summaryRow("重置", icon: "arrow.counterclockwise") {
                    if let reset = window?.resetDate {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(DisplayFormat.countdown(to: reset, now: context.date))
                        }
                        .help(DisplayFormat.dateTime.string(from: reset))
                    } else {
                        Text("—")
                    }
                }
                summaryRow("预测", icon: "speedometer") {
                    Text(forecastText).help(forecastHelp)
                }
                if let bucket = model.selectedBucket, bucket.primary != nil, let secondary = bucket.secondary {
                    summaryRow(cycleName(secondary), icon: "calendar") {
                        Text(secondary.usedPercent.map { "剩余 \(DisplayFormat.percent(max(0, min(100, 100 - $0))))" } ?? "—")
                            .help(secondary.resetDate.map { "重置于 \(DisplayFormat.dateTime.string(from: $0))" } ?? "重置时间未知")
                    }
                } else if isCurrent, let forecast = model.forecast {
                    summaryRow("速度", icon: "chart.line.uptrend.xyaxis") {
                        Text("\(String(format: "%.2f", forecast.percentPerHour))% / 小时")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryRow<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
            content().font(.system(size: 13, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
        }
    }

    private var forecastText: String {
        guard isCurrent, remaining != nil else { return "—" }
        if remaining == 0 { return "等待重置" }
        guard let forecast = model.forecast else { return "待积累" }
        return forecast.exhaustsBeforeReset
            ? "\(DisplayFormat.dateTime.string(from: forecast.exhaustedAt)) 耗尽"
            : "可用至重置"
    }

    private var forecastHelp: String {
        guard isCurrent else { return "更新成功后恢复预测" }
        if remaining == 0 { return "配额已用尽，等待重置" }
        guard let forecast = model.forecast else { return "需至少 4 个样本、15 分钟和 2% 用量变化" }
        return "\(model.forecastText)；每小时约 \(String(format: "%.2f", forecast.percentPerHour))%，基于 \(forecast.samples) 次观测"
    }

    private func cycleName(_ value: RateLimitWindow?) -> String {
        guard let minutes = value?.windowDurationMins else { return "本周期" }
        if minutes >= 24 * 60 { return "\(minutes / (24 * 60)) 天" }
        if minutes >= 60 { return "\(minutes / 60) 小时" }
        return "\(minutes) 分钟"
    }

    private func duration(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return hours > 0 ? "\(hours)时 \(minutes)分" : "\(minutes) 分钟"
    }
}

private struct DashboardMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 19, weight: .medium, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum HistoryRange: String, CaseIterable, Identifiable {
    case seven = "7 日"
    case thirty = "30 日"
    case ninety = "90 日"
    case all = "全部"

    var id: String { rawValue }
    var days: Int? {
        switch self {
        case .seven: return 7
        case .thirty: return 30
        case .ninety: return 90
        case .all: return nil
        }
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var range: HistoryRange = .thirty

    private var buckets: [DailyUsageBucket] {
        let values = model.snapshot?.usage.dailyUsageBuckets?.sorted { $0.startDate < $1.startDate } ?? []
        guard let days = range.days else { return values }
        return Array(values.suffix(days))
    }

    private var points: [DayPoint] {
        buckets.compactMap { bucket in
            guard let date = bucket.date else { return nil }
            return DayPoint(key: bucket.startDate, date: date, tokens: bucket.tokens)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Picker("时间范围", selection: $range) {
                        ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 250)
                    Spacer()
                    Menu {
                        Button("导出 CSV") { export(.csv) }
                        Button("导出 JSON") { export(.json) }
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                    .fixedSize().disabled(buckets.isEmpty)
                }
                HistoryChart(points: points, title: "每日 token", height: 170)
                Divider()
                HStack(spacing: 20) {
                    DashboardMetric(title: "总 token", value: buckets.isEmpty ? "—" : DisplayFormat.tokens(buckets.map(\.tokens).reduce(0, +)))
                    DashboardMetric(title: "日均", value: DisplayFormat.tokens(average))
                    DashboardMetric(title: "峰值", value: DisplayFormat.tokens(buckets.map(\.tokens).max()))
                    DashboardMetric(title: "有数据日", value: "\(buckets.count) 天")
                }
                .help("未结算日期保持空白，日均按有数据日期计算")
                if !buckets.isEmpty {
                    Divider()
                    DisclosureGroup("每日明细") {
                        dailyRecords.padding(.top, 8)
                    }
                    .font(.system(size: 11))
                }
            }
            .padding(22)
        }
    }

    private var dailyRecords: some View {
        VStack(spacing: 0) {
            ForEach(Array(buckets.reversed())) { bucket in
                HStack {
                    Text(bucket.date.map { DisplayFormat.day.string(from: $0) } ?? bucket.startDate)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(bucket.tokens.formatted()).monospacedDigit()
                    Text("token").foregroundStyle(.tertiary)
                }
                .font(.system(size: 11)).padding(.vertical, 7)
                Divider()
            }
        }
    }

    private var average: Int64? {
        guard !buckets.isEmpty else { return nil }
        return buckets.map(\.tokens).reduce(0, +) / Int64(buckets.count)
    }

    private func export(_ format: ExportFormat) {
        if let snapshot = model.snapshot { ExportService.export(snapshot, format: format, range: range.days) }
    }
}

struct HistoryChart: View {
    let points: [DayPoint]
    let title: String
    var height: CGFloat = 145

    private var available: [DayPoint] { points.filter { $0.tokens != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(available.last.map { "截至 \(DisplayFormat.day.string(from: $0.date))" } ?? "")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if available.isEmpty {
                Label("暂无历史记录", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).frame(height: height)
            } else {
                Chart(available) { point in
                    BarMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("Token", point.tokens ?? 0)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.75))
                    .cornerRadius(2)
                    .accessibilityLabel(DisplayFormat.day.string(from: point.date))
                    .accessibilityValue("\(point.tokens ?? 0) token")
                }
                .chartYScale(domain: 0...max(1, Double(available.compactMap(\.tokens).max() ?? 0) * 1.12))
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine().foregroundStyle(.primary.opacity(0.06))
                        AxisValueLabel {
                            if let raw = value.as(Int64.self) { Text(DisplayFormat.tokens(raw)) }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(7, available.count))) { _ in
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartPlotStyle { plot in plot.padding(.top, 4) }
                .frame(height: height)
                .accessibilityLabel("\(title)图表")
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("菜单栏样式")
                    Spacer()
                    Picker("菜单栏样式", selection: $settings.menuStyle) {
                        ForEach(MenuDisplayStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 250)
                }
                Divider()
                HStack {
                    Text("配额与重置通知")
                    Spacer()
                    Button("测试通知", action: model.sendTestNotification)
                        .disabled(!settings.notificationsEnabled).controlSize(.small)
                    Toggle("配额与重置通知", isOn: $settings.notificationsEnabled)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .onChange(of: settings.notificationsEnabled) { enabled in
                            if enabled { model.requestNotificationAuthorization() }
                        }
                }
                HStack {
                    Text("提醒阈值").foregroundStyle(.secondary)
                    Spacer()
                    Toggle("70%", isOn: $settings.threshold70)
                    Toggle("85%", isOn: $settings.threshold85)
                    Toggle("95%", isOn: $settings.threshold95)
                }
                .toggleStyle(.checkbox).disabled(!settings.notificationsEnabled)
                HStack {
                    Text("安静时段")
                    Spacer()
                    if settings.quietHoursEnabled {
                        DatePicker("开始", selection: minutesBinding($settings.quietStartMinutes), displayedComponents: .hourAndMinute)
                            .labelsHidden().fixedSize()
                        Text("至").foregroundStyle(.secondary)
                        DatePicker("结束", selection: minutesBinding($settings.quietEndMinutes), displayedComponents: .hourAndMinute)
                            .labelsHidden().fixedSize()
                    }
                    Toggle("安静时段", isOn: $settings.quietHoursEnabled)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                .help("安静时段内暂停配额通知")
                Divider()
                HStack {
                    Text("登录时自动启动")
                    Spacer()
                    Toggle("登录时自动启动", isOn: Binding(get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                .help(settings.launchStatus)
                Divider()
                DisclosureGroup("数据与隐私") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("只通过本机 Codex 读取用量，不读取凭据、会话或项目内容。")
                        Text(model.coverageText)
                        Text(AppFiles.state.path).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    }
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
                DisclosureGroup("诊断") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.diagnosticsText).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        HStack {
                            Button("复制诊断", action: model.copyDiagnostics)
                            Button("立即刷新", action: model.refresh).disabled(model.isRefreshing)
                        }
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
            }
            .font(.system(size: 12)).padding(22)
        }
        .onAppear { settings.refreshLaunchStatus() }
    }

    private func minutesBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60)) ?? Date()
            },
            set: { date in
                let values = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (values.hour ?? 0) * 60 + (values.minute ?? 0)
            }
        )
    }
}
