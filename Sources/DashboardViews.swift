import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in content }
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Picker("页面", selection: $model.dashboardTab) {
                    Text("概览").tag(DashboardTab.overview)
                    Text("历史").tag(DashboardTab.history)
                    Text("设置").tag(DashboardTab.settings)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 228)
                Spacer()
                Button(action: model.refresh) {
                    ZStack {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                            .opacity(model.isRefreshing ? 0 : 1)
                        if model.isRefreshing { ProgressView().controlSize(.small) }
                    }
                    .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.borderless).disabled(model.isRefreshing)
                .accessibilityLabel(model.isRefreshing ? "正在刷新用量" : "刷新用量")
                .help("刷新用量 ⌘R").keyboardShortcut("r", modifiers: .command)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
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
                Circle().fill(statusColor).frame(width: 5, height: 5).accessibilityHidden(true)
                Text(statusText).lineLimit(1).help(model.lastError ?? statusText)
                Spacer()
                if let bucket = model.selectedBucket {
                    Text("\(bucket.displayName) · \(bucket.planName)")
                        .lineLimit(1)
                }
            }
            .font(UITheme.caption).foregroundStyle(UITheme.secondaryText)
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .frame(minWidth: 720, minHeight: 500)
        .background(UITheme.shell)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .tint(UITheme.accent)
    }

    private var statusColor: Color {
        if model.lastError != nil { return UITheme.warning }
        return model.dataState == .current ? UITheme.positive : UITheme.secondaryText
    }

    private var statusText: String {
        if model.isRefreshing { return "正在更新…" }
        if model.lastError != nil { return model.snapshot == nil ? "读取失败 · 点击刷新重试" : "更新失败 · 显示缓存" }
        guard let snapshot = model.snapshot else { return "等待数据" }
        if model.dataState != .current { return "\(model.dataState.title) · \(DisplayFormat.dateTime.string(from: snapshot.fetchedAt))" }
        return "更新于 \(DisplayFormat.dateTime.string(from: snapshot.fetchedAt))"
    }
}

struct OverviewView: View {
    @ObservedObject var model: AppModel

    private var window: RateLimitWindow? { model.selectedWindow }
    private var remaining: Double? { window?.usedPercent.map { max(0, min(100, 100 - $0)) } }
    private var isCurrent: Bool { model.dataState == .current }
    private var tint: Color {
        guard isCurrent else { return UITheme.secondaryText }
        if model.risk == .critical { return UITheme.critical }
        if model.risk == .watch { return UITheme.warning }
        return UITheme.accent
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                quotaSummary
                HistoryChart(
                    points: UsageStatistics.dayPoints(buckets: model.snapshot?.usage.dailyUsageBuckets ?? [], days: 30),
                    title: "近 30 日用量", height: 128
                )
                .insetSurface()
                HStack(spacing: 20) {
                    DashboardMetric(title: "累计 token", value: DisplayFormat.tokens(model.summary?.lifetimeTokens))
                    DashboardMetric(title: "单日峰值", value: DisplayFormat.tokens(model.summary?.peakDailyTokens))
                    DashboardMetric(title: "最长任务", value: model.summary?.longestRunningTurnSec.map(duration) ?? "—")
                    DashboardMetric(title: "连续使用", value: model.summary?.currentStreakDays.map { "\($0) 天" } ?? "—")
                }
                .help(model.insight)
            }
            .padding(20)
        }
    }

    private var quotaSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if model.buckets.count > 1 {
                    Picker("配额", selection: Binding(
                        get: { model.selectedBucket?.id ?? "" }, set: model.selectBucket
                    )) {
                        ForEach(model.buckets) { Text($0.displayName).tag($0.id) }
                    }
                    .labelsHidden().pickerStyle(.menu).controlSize(.small)
                    .frame(maxWidth: 180, alignment: .leading)
                } else {
                    Text(model.selectedBucket?.displayName ?? "当前配额").font(UITheme.section)
                }
                Text(cycleName(window)).font(UITheme.caption).foregroundStyle(UITheme.secondaryText)
                Text("已用 \(DisplayFormat.percent(window?.usedPercent))")
                    .font(UITheme.caption).foregroundStyle(UITheme.secondaryText)
                Spacer()
                if isCurrent, remaining != nil, model.risk != .unknown {
                    Label(remaining == 0 ? "已用尽" : model.risk.title,
                          systemImage: remaining == 0 || model.risk != .healthy ? "exclamationmark.circle" : "checkmark.circle")
                        .font(UITheme.caption).foregroundStyle(tint)
                }
            }
            HStack(alignment: .center, spacing: 24) {
                QuotaGauge(value: remaining, isCurrent: isCurrent, height: 160)
                    .frame(maxWidth: .infinity)
                Divider().frame(height: 120)
                VStack(alignment: .leading, spacing: 10) {
                    summaryRow("重置", icon: "arrow.counterclockwise") {
                        if let reset = window?.resetDate {
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                Text(reset <= context.date ? "等待更新" : DisplayFormat.countdown(to: reset, now: context.date))
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
        .insetSurface()
    }

    private func summaryRow<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(title, systemImage: icon)
                .font(UITheme.caption).foregroundStyle(UITheme.secondaryText).frame(width: 66, alignment: .leading)
            content().font(UITheme.body).lineLimit(1).minimumScaleFactor(0.85)
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
            Text(title).font(UITheme.caption).foregroundStyle(UITheme.secondaryText)
            Text(value).font(.system(size: 24, weight: .medium, design: .rounded))
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
                    .help("按最近 7、30 或 90 条已记录日数据筛选")
                    Spacer()
                    Menu {
                        Button("导出 CSV") { export(.csv) }
                        Button("导出 JSON") { export(.json) }
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                    .fixedSize().disabled(buckets.isEmpty)
                }
                HistoryChart(points: points, title: "每日 token", height: 156)
                    .insetSurface()
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
                    .font(UITheme.body)
                }
            }
            .padding(20)
        }
    }

    private var dailyRecords: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(buckets.reversed())) { bucket in
                HStack {
                    Text(bucket.date.map { DisplayFormat.day.string(from: $0) } ?? bucket.startDate)
                        .foregroundStyle(UITheme.secondaryText)
                    Spacer()
                    Text(bucket.tokens.formatted()).monospacedDigit()
                    Text("token").foregroundStyle(UITheme.secondaryText)
                }
                .font(UITheme.body).padding(.vertical, 8)
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

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("外观") {
                Picker("菜单栏样式", selection: $settings.menuStyle) {
                    ForEach(MenuDisplayStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("通知") {
                Toggle("配额与重置通知", isOn: $settings.notificationsEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: settings.notificationsEnabled) { enabled in
                        if enabled { model.requestNotificationAuthorization() }
                    }
                LabeledContent("提醒阈值") {
                    HStack(spacing: 16) {
                        Toggle("70%", isOn: $settings.threshold70)
                        Toggle("85%", isOn: $settings.threshold85)
                        Toggle("95%", isOn: $settings.threshold95)
                    }
                    .toggleStyle(.checkbox).disabled(!settings.notificationsEnabled)
                }
                Toggle("安静时段", isOn: $settings.quietHoursEnabled)
                    .toggleStyle(.switch)
                    .help("安静时段内暂停配额通知")
                if settings.quietHoursEnabled {
                    HStack(spacing: 24) {
                        DatePicker("开始", selection: minutesBinding($settings.quietStartMinutes), displayedComponents: .hourAndMinute)
                        DatePicker("结束", selection: minutesBinding($settings.quietEndMinutes), displayedComponents: .hourAndMinute)
                    }
                }
                LabeledContent("通知测试") {
                    Button("发送测试通知", action: model.sendTestNotification)
                        .disabled(!settings.notificationsEnabled)
                }
            }

            Section("系统") {
                Toggle("登录时自动启动", isOn: Binding(
                    get: { settings.launchAtLogin }, set: settings.setLaunchAtLogin
                ))
                .toggleStyle(.switch)
                .help(settings.launchStatus)
                if settings.launchStatus != "已启用", settings.launchStatus != "未启用" {
                    Label(settings.launchStatus, systemImage: "info.circle")
                        .font(UITheme.caption).foregroundStyle(UITheme.warning)
                }
            }

            Section {
                DisclosureGroup("数据与隐私") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("只通过本机 Codex 读取用量，不读取凭据、会话或项目内容。")
                        Text(model.coverageText)
                        Text(AppFiles.state.path)
                            .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    }
                    .font(UITheme.caption).foregroundStyle(UITheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }
                DisclosureGroup("诊断") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.diagnosticsText)
                            .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        HStack(spacing: 12) {
                            Button("复制诊断", action: model.copyDiagnostics)
                            Button("立即刷新", action: model.refresh).disabled(model.isRefreshing)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }
            }
        }
        .formStyle(.grouped)
        .font(UITheme.body)
        .scrollContentBackground(.hidden)
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
