import AppKit
import Charts
import SwiftUI

extension RiskLevel {
    var color: Color {
        switch self {
        case .healthy: return .green
        case .watch: return .orange
        case .critical: return .red
        case .unknown: return .secondary
        }
    }

    var symbol: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .watch: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

extension View {
    func quotaCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.20), .white.opacity(0.035), .blue.opacity(0.035)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.52), .white.opacity(0.10), .primary.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            }
            .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 7)
    }
}

struct StatusLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            switch settings.menuStyle {
            case .compact:
                Text(DisplayFormat.percent(model.remainingPercent))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            case .standard, .full:
                VStack(alignment: .leading, spacing: -3) {
                    HStack(spacing: 3) {
                        Text(settings.menuStyle == .full ? "GPT · \(shortReset)" : "GPT")
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        Circle()
                            .fill(model.risk.color)
                            .frame(width: 4, height: 4)
                    }
                    Text(DisplayFormat.percent(model.remainingPercent))
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(minWidth: settings.menuStyle == .full ? 54 : 35, alignment: .leading)
            }
        }
        .frame(height: 22)
        .onAppear {
            model.start()
            if CommandLine.arguments.contains("--show-dashboard") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "dashboard")
            }
        }
        .accessibilityLabel("GPT 用量，剩余 \(DisplayFormat.percent(model.remainingPercent))，\(model.risk.title)")
    }

    private var shortReset: String {
        guard let date = model.selectedWindow?.resetDate else { return "—" }
        let hours = max(0, Int(date.timeIntervalSinceNow / 3_600))
        return hours >= 24 ? "\(hours / 24)d" : "\(hours)h"
    }
}

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Circle()
                .fill(.blue.opacity(0.22))
                .frame(width: 260, height: 260)
                .blur(radius: 72)
                .offset(x: -170, y: -250)
            Circle()
                .fill(.cyan.opacity(0.16))
                .frame(width: 220, height: 220)
                .blur(radius: 76)
                .offset(x: 170, y: 80)
            Circle()
                .fill(.purple.opacity(0.10))
                .frame(width: 190, height: 190)
                .blur(radius: 72)
                .offset(x: -120, y: 280)
            LinearGradient(
                colors: [.white.opacity(0.12), .clear, .black.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ScrollView {
                VStack(spacing: 12) {
                    header
                    quotaHero
                    metrics
                    MiniUsageChart(points: model.dayPoints7, coverageText: model.coverageText)
                    insight
                    footer
                }
                .padding(15)
            }
        }
        .frame(width: 430, height: 610)
    }

    private var header: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan.opacity(0.82)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "gauge.with.dots.needle.67percent")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)
                .shadow(color: .blue.opacity(0.28), radius: 9, y: 4)

                VStack(alignment: .leading, spacing: 1) {
                    Text("GPT 用量")
                        .font(.system(size: 15.5, weight: .semibold))
                    Text("\(model.selectedBucket?.displayName ?? "Codex") · \(model.selectedBucket?.planName ?? "ChatGPT")")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(model.risk.title, systemImage: model.risk.symbol)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(model.risk.color)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay { Capsule().stroke(model.risk.color.opacity(0.20), lineWidth: 0.6) }
                Button(action: model.refresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(.ultraThinMaterial, in: Circle())
                        .rotationEffect(model.isRefreshing ? .degrees(360) : .zero)
                        .animation(model.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: model.isRefreshing)
                }
                .buttonStyle(.plain)
                .disabled(model.isRefreshing)
                .help("立即更新")
            }
            if model.buckets.count > 1 {
                Picker("", selection: Binding(
                    get: { model.selectedBucket?.id ?? "" },
                    set: model.selectBucket
                )) {
                    ForEach(model.buckets) { bucket in
                        Text(bucket.displayName).tag(bucket.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
        }
    }

    private var quotaHero: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(.primary.opacity(0.075), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: CGFloat((model.remainingPercent ?? 0) / 100))
                    .stroke(
                        AngularGradient(colors: [.blue, .cyan, .mint, .blue], center: .center),
                        style: StrokeStyle(lineWidth: 9, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .cyan.opacity(0.28), radius: 7)
                Circle()
                    .fill(.ultraThinMaterial)
                    .padding(13)
                VStack(spacing: -2) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(model.remainingPercent.map { String(Int($0.rounded())) } ?? "—")
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        if model.remainingPercent != nil {
                            Text("%")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("剩余")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 108, height: 108)
            .accessibilityLabel("剩余配额 \(DisplayFormat.percent(model.remainingPercent))")

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前配额窗口")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(DisplayFormat.countdown(to: model.selectedWindow?.resetDate)) 后重置")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                HStack(spacing: 6) {
                    Image(systemName: model.forecast?.exhaustsBeforeReset == true ? "exclamationmark.triangle.fill" : "waveform.path.ecg")
                    Text(model.forecastText)
                        .lineLimit(2)
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(model.forecast?.exhaustsBeforeReset == true ? Color.red : Color.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.primary.opacity(0.045), in: Capsule())

                HStack(spacing: 5) {
                    Text("已使用 \(DisplayFormat.percent(model.usedPercent))")
                    Text("·")
                    Text((model.selectedWindow?.resetDate).map { DisplayFormat.dateTime.string(from: $0) } ?? "等待更新")
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(17)
        .quotaCard(cornerRadius: 23)
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            MetricTile(
                icon: "calendar",
                title: "最近完整日",
                value: DisplayFormat.tokens(model.latestDaily?.tokens),
                subtitle: model.latestDaily?.date.map(DisplayFormat.day.string) ?? "暂无数据"
            )
            MetricTile(
                icon: "chart.bar.fill",
                title: "7 日均值",
                value: DisplayFormat.tokens(model.average7),
                subtitle: "token / 日"
            )
            MetricTile(
                icon: "flame.fill",
                title: "连续使用",
                value: model.summary?.currentStreakDays.map { "\($0) 天" } ?? "—",
                subtitle: "最长 \(model.summary?.longestStreakDays.map(String.init) ?? "—") 天"
            )
            MetricTile(
                icon: "arrow.counterclockwise.circle.fill",
                title: "重置券",
                value: "\(model.resetCredits) 张",
                subtitle: model.resetCredits > 0 ? "只读展示" : "当前无可用"
            )
        }
    }

    private var insight: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("用量洞察")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(model.insight)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .quotaCard()
    }

    private var footer: some View {
        VStack(spacing: 9) {
            HStack {
                Circle()
                    .fill(model.lastError == nil ? (model.dataIsStale ? Color.orange : Color.green) : Color.red)
                    .frame(width: 6, height: 6)
                Text(model.refreshText)
                    .lineLimit(1)
                    .help(model.lastError ?? "")
                Spacer()
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)

            HStack {
                Button("打开详情") {
                    model.dashboardTab = .overview
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "dashboard")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("设置") {
                    model.dashboardTab = .settings
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "dashboard")
                }
                Button("退出") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
    }
}

struct MetricTile: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 28, height: 28)
                .background(.blue.opacity(0.11), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(subtitle)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .quotaCard(cornerRadius: 13)
    }
}

struct MiniUsageChart: View {
    let points: [DayPoint]
    let coverageText: String

    private var available: [DayPoint] { points.filter { $0.tokens != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("近 7 日 token")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(coverageText)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            if available.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 24))
                    Text("暂无每日数据")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                    .frame(height: 92)
            } else {
                Chart(available) { point in
                    BarMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("Token", point.tokens ?? 0)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .bottom, endPoint: .top)
                    )
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                        AxisGridLine().foregroundStyle(.clear)
                        AxisTick().foregroundStyle(.clear)
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 94)
                .accessibilityLabel("近 7 日 token 用量图")
            }
        }
        .padding(12)
        .quotaCard()
    }
}

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GPT 用量")
                        .font(.system(size: 21, weight: .semibold))
                    Text("本地 Codex / ChatGPT 用量仪表盘")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(model.risk.title, systemImage: model.risk.symbol)
                    .foregroundStyle(model.risk.color)
                    .font(.system(size: 11, weight: .semibold))
                Button(action: model.refresh) { Image(systemName: "arrow.clockwise") }
                    .disabled(model.isRefreshing)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)

            Picker("", selection: $model.dashboardTab) {
                ForEach(DashboardTab.allCases) { tab in Text(tab.rawValue).tag(tab) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 22)
            .padding(.bottom, 12)

            Divider()

            Group {
                switch model.dashboardTab {
                case .overview: OverviewView(model: model)
                case .history: HistoryView(model: model)
                case .settings: SettingsView(model: model, settings: settings)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 590)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                RadialGradient(
                    colors: [.blue.opacity(0.11), .clear],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: 640
                )
                RadialGradient(
                    colors: [.cyan.opacity(0.07), .clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: 580
                )
            }
        }
    }
}

struct OverviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(
                    columns: model.buckets.count == 1
                        ? [GridItem(.flexible())]
                        : [GridItem(.adaptive(minimum: 300), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(model.buckets) { bucket in
                        RateLimitCard(bucket: bucket, isSelected: bucket.id == model.selectedBucket?.id, risk: bucket.id == model.selectedBucket?.id ? model.risk : .unknown) {
                            model.selectBucket(bucket.id)
                        }
                    }
                }

                HStack(spacing: 12) {
                    DashboardMetric(title: "累计 token", value: DisplayFormat.tokens(model.summary?.lifetimeTokens), icon: "sum")
                    DashboardMetric(title: "单日峰值", value: DisplayFormat.tokens(model.summary?.peakDailyTokens), icon: "chart.line.uptrend.xyaxis")
                    DashboardMetric(title: "最长任务", value: model.summary?.longestRunningTurnSec.map(duration) ?? "—", icon: "timer")
                    DashboardMetric(title: "连续使用", value: model.summary?.currentStreakDays.map { "\($0) 天" } ?? "—", icon: "flame")
                }

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("耗尽预测", systemImage: "gauge.with.dots.needle.50percent")
                            .font(.system(size: 13, weight: .semibold))
                        Text(model.forecastText)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        if let forecast = model.forecast {
                            Text("观测速率 \(String(format: "%.2f", forecast.percentPerHour))% / 小时 · \(forecast.samples) 个样本")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("需至少 4 个样本、15 分钟和 2% 用量变化")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .quotaCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("用量洞察", systemImage: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Text(model.insight)
                            .font(.system(size: 16, weight: .semibold))
                        Text("\(model.coverageText) · \(model.refreshText)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .quotaCard()
                }

                HistoryChart(points: UsageStatistics.dayPoints(buckets: model.snapshot?.usage.dailyUsageBuckets ?? [], days: 30), title: "近 30 日 token")
            }
            .padding(22)
        }
    }

    private func duration(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        return hours > 0 ? "\(hours)小时\(minutes)分" : "\(minutes) 分钟"
    }
}

struct RateLimitCard: View {
    let bucket: RateLimitBucket
    let isSelected: Bool
    let risk: RiskLevel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bucket.displayName).font(.system(size: 14, weight: .semibold))
                        Text("\(bucket.planName) · \(windowName)")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(bucket.activeWindow?.remainingPercent.rounded() ?? 0))% 剩余")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                ProgressView(value: bucket.activeWindow?.usedPercent ?? 0, total: 100)
                    .tint(isSelected ? risk.color : .blue)
                HStack {
                    Text("已使用 \(DisplayFormat.percent(bucket.activeWindow?.usedPercent))")
                    Spacer()
                    Text("\(DisplayFormat.countdown(to: bucket.activeWindow?.resetDate)) 后重置")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            }
            .padding(15)
            .background(isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(isSelected ? Color.blue.opacity(0.5) : Color.primary.opacity(0.07), lineWidth: isSelected ? 1.2 : 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    private var windowName: String {
        guard let minutes = bucket.activeWindow?.windowDurationMins else { return "当前窗口" }
        if minutes >= 7 * 24 * 60 { return "\(minutes / (24 * 60)) 天窗口" }
        if minutes >= 60 { return "\(minutes / 60) 小时窗口" }
        return "\(minutes) 分钟窗口"
    }
}

struct DashboardMetric: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .quotaCard()
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
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Picker("时间范围", selection: $range) {
                        ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 330)
                    Spacer()
                    Button("CSV") {
                        if let snapshot = model.snapshot { ExportService.export(snapshot, format: .csv, range: range.days) }
                    }
                    Button("JSON") {
                        if let snapshot = model.snapshot { ExportService.export(snapshot, format: .json, range: range.days) }
                    }
                }

                HStack(spacing: 12) {
                    DashboardMetric(title: "总 token", value: DisplayFormat.tokens(buckets.map(\.tokens).reduce(0, +)), icon: "sum")
                    DashboardMetric(title: "日均", value: DisplayFormat.tokens(average), icon: "divide")
                    DashboardMetric(title: "峰值", value: DisplayFormat.tokens(buckets.map(\.tokens).max()), icon: "arrow.up.right")
                    DashboardMetric(title: "有数据日", value: "\(buckets.count) 天", icon: "calendar.badge.checkmark")
                }

                HistoryChart(points: points, title: "\(range.rawValue) token 趋势")
                    .frame(minHeight: 330)

                Text("每日数据直接来自 Codex `account/usage/read`。服务端尚未结算的日期保持空白，不使用本地估算值补齐。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(22)
        }
    }

    private var average: Int64? {
        guard !buckets.isEmpty else { return nil }
        return buckets.map(\.tokens).reduce(0, +) / Int64(buckets.count)
    }
}

struct HistoryChart: View {
    let points: [DayPoint]
    let title: String

    private var available: [DayPoint] { points.filter { $0.tokens != nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(available.last.map { DisplayFormat.day.string(from: $0.date) } ?? "—")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if available.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 30))
                    Text("暂无 token 历史")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                    .frame(minHeight: 230)
            } else {
                Chart(available) { point in
                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value("Token", point.tokens ?? 0)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [.blue.opacity(0.38), .blue.opacity(0.03)], startPoint: .top, endPoint: .bottom)
                    )
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("Token", point.tokens ?? 0)
                    )
                    .foregroundStyle(.blue)
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("Token", point.tokens ?? 0)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(available.count > 45 ? 4 : 18)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(.primary.opacity(0.06))
                        AxisValueLabel {
                            if let raw = value.as(Int64.self) { Text(DisplayFormat.tokens(raw)) }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(8, available.count))) { value in
                        AxisGridLine().foregroundStyle(.clear)
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .frame(minHeight: 230)
                .accessibilityLabel("\(title)图表")
            }
        }
        .padding(16)
        .quotaCard()
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsGroup("外观", icon: "paintpalette") {
                    Picker("菜单栏样式", selection: $settings.menuStyle) {
                        ForEach(MenuDisplayStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                settingsGroup("通知", icon: "bell") {
                    Toggle("启用配额与重置通知", isOn: $settings.notificationsEnabled)
                        .onChange(of: settings.notificationsEnabled) { enabled in
                            if enabled { model.requestNotificationAuthorization() }
                        }
                    HStack {
                        Toggle("70%", isOn: $settings.threshold70)
                        Toggle("85%", isOn: $settings.threshold85)
                        Toggle("95%", isOn: $settings.threshold95)
                        Spacer()
                        Button("测试通知", action: model.sendTestNotification)
                            .disabled(!settings.notificationsEnabled)
                    }
                    Toggle("安静时段", isOn: $settings.quietHoursEnabled)
                    if settings.quietHoursEnabled {
                        HStack {
                            DatePicker("开始", selection: minutesBinding($settings.quietStartMinutes), displayedComponents: .hourAndMinute)
                            DatePicker("结束", selection: minutesBinding($settings.quietEndMinutes), displayedComponents: .hourAndMinute)
                        }
                    }
                }

                settingsGroup("系统", icon: "gearshape") {
                    Toggle("登录时自动启动", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: settings.setLaunchAtLogin
                    ))
                    Text(settings.launchStatus)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                settingsGroup("数据与隐私", icon: "hand.raised") {
                    Text("数据仅通过本地 codex app-server 读取。组件不读取 cookie、OAuth token、API key、会话、代码或项目路径。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\(model.coverageText) · 本地缓存 \(AppFiles.state.path)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }

                settingsGroup("脱敏诊断", icon: "stethoscope") {
                    Text(model.diagnosticsText)
                        .font(.system(size: 10.5, design: .monospaced))
                        .textSelection(.enabled)
                    HStack {
                        Button("复制诊断", action: model.copyDiagnostics)
                        Button("立即刷新", action: model.refresh)
                        Spacer()
                    }
                }
            }
            .padding(22)
        }
        .onAppear { settings.refreshLaunchStatus() }
    }

    private func settingsGroup<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .quotaCard()
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

