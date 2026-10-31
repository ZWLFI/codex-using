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
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.24), .white.opacity(0.05), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.60), .white.opacity(0.14), .primary.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: .black.opacity(0.13), radius: 14, x: 0, y: 7)
    }
}

struct NativeGlassBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

struct GlassBackdrop: View {
    let material: NSVisualEffectView.Material

    var body: some View {
        ZStack {
            NativeGlassBackground(material: material)
            LinearGradient(
                colors: [.white.opacity(0.17), .clear, .black.opacity(0.055)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [.blue.opacity(0.10), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 380
            )
        }
    }
}

enum StatusItemArtwork {
    static func image(style: MenuDisplayStyle, remaining: Double?, resetDate: Date?) -> NSImage {
        let percent = DisplayFormat.percent(remaining)
        switch style {
        case .compact:
            return oneLine(percent)
        case .standard:
            return twoLine(top: "GPT", bottom: percent, width: 36)
        case .full:
            return twoLine(top: "GPT", bottom: "\(percent) · \(shortReset(resetDate))", width: 62)
        }
    }

    private static func oneLine(_ text: String) -> NSImage {
        let width = max(30, CGFloat(text.count) * 8)
        return templateImage(width: width, height: 22) { rect in
            draw(
                text,
                in: rect.insetBy(dx: 0, dy: 3),
                font: .monospacedDigitSystemFont(ofSize: 11.5, weight: .bold)
            )
        }
    }

    private static func twoLine(top: String, bottom: String, width: CGFloat) -> NSImage {
        templateImage(width: width, height: 22) { _ in
            draw(top, in: NSRect(x: 0, y: 0, width: width, height: 9), font: .systemFont(ofSize: 7.2, weight: .medium))
            draw(bottom, in: NSRect(x: 0, y: 8, width: width, height: 14), font: .monospacedDigitSystemFont(ofSize: 11.2, weight: .bold))
        }
    }

    private static func templateImage(
        width: CGFloat,
        height: CGFloat,
        drawing: @escaping (NSRect) -> Void
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { rect in
            drawing(rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(_ text: String, in rect: NSRect, font: NSFont) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph
            ]
        )
    }

    private static func shortReset(_ date: Date?) -> String {
        guard let date else { return "—" }
        let hours = max(0, Int(date.timeIntervalSinceNow / 3_600))
        return hours >= 24 ? "\(hours / 24)d" : "\(hours)h"
    }
}

struct StatusLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: StatusItemArtwork.image(
            style: settings.menuStyle,
            remaining: model.remainingPercent,
            resetDate: model.selectedWindow?.resetDate
        ))
        .interpolation(.high)
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
}

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ZStack {
            GlassBackdrop(material: .popover)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    if model.buckets.count > 1 {
                        bucketPicker
                    }
                    quotaHero
                    WeeklyPercentChart(points: model.dailyPercentPoints7)
                    footer
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
        }
        .frame(width: 370, height: 350)
    }

    private var bucketPicker: some View {
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

    private var quotaHero: some View {
        HStack(spacing: 14) {
            Button(action: model.refresh) {
                ZStack {
                    Circle()
                        .stroke(.primary.opacity(0.09), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: CGFloat((model.remainingPercent ?? 0) / 100))
                        .stroke(
                            AngularGradient(colors: [.blue, .cyan, .blue], center: .center),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: .blue.opacity(0.30), radius: 6)
                    Circle()
                        .fill(.thinMaterial)
                        .padding(12)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.34), lineWidth: 0.7)
                                .padding(12)
                        }
                    VStack(spacing: -2) {
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text(model.remainingPercent.map { String(Int($0.rounded())) } ?? "—")
                                .font(.system(size: 25, weight: .bold, design: .rounded))
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
            }
            .buttonStyle(.plain)
            .disabled(model.isRefreshing)
            .frame(width: 90, height: 90)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("本周期剩余")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(DisplayFormat.countdown(to: model.selectedWindow?.resetDate)) 后重置")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .quotaCard(cornerRadius: 20)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.lastError == nil ? (model.dataIsStale ? Color.orange : Color.green) : Color.red)
                .frame(width: 6, height: 6)
            Text(model.refreshText)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(model.lastError ?? "")
            Spacer(minLength: 6)
            Button {
                    model.dashboardTab = .overview
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "dashboard")
                } label: {
                    Label("详情", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
            Button {
                    model.dashboardTab = .settings
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "dashboard")
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("设置")
            Button(action: { NSApp.terminate(nil) }) {
                Image(systemName: "power")
            }
            .help("退出")
        }
        .controlSize(.small)
    }
}

struct WeeklyPercentChart: View {
    let points: [DailyPercentPoint]
    private let barAreaHeight: CGFloat = 92

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    private var scaleMaximum: Double {
        max(10, (points.compactMap(\.value).max() ?? 0) * 1.12)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近 7 天")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("每日配额使用")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(points) { point in
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            VStack(spacing: 4) {
                                Text(point.value.map { "\(Int($0.rounded()))%" } ?? "—")
                                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(point.value == nil ? Color.secondary : Color.primary)
                                    .monospacedDigit()

                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: point.value == nil
                                                ? [.secondary.opacity(0.16), .secondary.opacity(0.08)]
                                                : [.blue, .cyan.opacity(0.78)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [.white.opacity(0.55), .white.opacity(0.06)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ),
                                                lineWidth: 0.7
                                            )
                                    }
                                    .shadow(color: .blue.opacity(point.value == nil ? 0 : 0.20), radius: 4, y: 3)
                                    .frame(height: barHeight(for: point.value))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: barAreaHeight, alignment: .bottom)

                        Text(Self.dayFormatter.string(from: point.date))
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .quotaCard()
    }

    private func barHeight(for value: Double?) -> CGFloat {
        guard let value else { return 2 }
        return max(2, (barAreaHeight - 18) * CGFloat(value / scaleMaximum))
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
        .background { GlassBackdrop(material: .underWindowBackground) }
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

