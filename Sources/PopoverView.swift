import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var hasCurrentData: Bool { model.lastError == nil && !model.dataIsStale }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 18) {
                header
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(model.remainingPercent.map { String(Int($0.rounded())) } ?? "—")
                                .font(.system(size: 48, weight: .medium, design: .rounded))
                                .tracking(-1.5)
                            if model.remainingPercent != nil {
                                Text("%")
                                    .font(.system(size: 22, weight: .regular, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .monospacedDigit()
                        Text("剩余配额").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 112, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("剩余配额 \(DisplayFormat.percent(model.remainingPercent))")
                    VStack(alignment: .leading, spacing: 13) {
                        compactMetric("重置", value: shortCountdown(to: model.selectedWindow?.resetDate, now: context.date))
                            .help(model.selectedWindow?.resetDate.map { DisplayFormat.dateTime.string(from: $0) } ?? "暂无重置时间")
                        compactMetric("预计可用", value: availability(now: context.date), warning: hasCurrentData && model.risk == .critical)
                            .help(!hasCurrentData ? "更新后显示预测" : model.remainingPercent == 0 ? "配额已用尽，等待重置" : model.forecastText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                GeometryReader { proxy in
                    Capsule().fill(.primary.opacity(0.07))
                    Capsule().fill(Color.accentColor)
                        .frame(width: proxy.size.width * CGFloat((model.remainingPercent ?? 0) / 100))
                }
                .frame(height: 5)
                .accessibilityHidden(true)
                .help("已使用 \(DisplayFormat.percent(model.selectedWindow?.usedPercent))")
                Divider().opacity(0.5)
                WeeklyPercentChart(points: model.dailyPercentPoints7) { openDashboard(.history) }
                footer
            }
            .padding(20)
        }
        .frame(width: 344)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 7) {
            if model.buckets.count > 1 {
                Menu {
                    Picker("配额", selection: Binding(
                        get: { model.selectedBucket?.id ?? "" }, set: model.selectBucket
                    )) {
                        ForEach(model.buckets) { bucket in Text(bucket.displayName).tag(bucket.id) }
                    }
                } label: {
                    Text(model.selectedBucket?.displayName ?? "Codex")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("选择配额")
            } else {
                Text(model.selectedBucket?.displayName ?? "Codex")
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            if let bucket = model.selectedBucket {
                Text(bucket.planName)
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.primary.opacity(0.05), in: Capsule())
            }
            Spacer(minLength: 6)
            Button(action: model.refresh) {
                ZStack {
                    Image(systemName: "arrow.clockwise").opacity(model.isRefreshing ? 0 : 1)
                    if model.isRefreshing { ProgressView().controlSize(.mini) }
                }
                .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.borderless).disabled(model.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .help("刷新 ⌘R").accessibilityLabel("刷新用量")
            Menu {
                Button("设置…", systemImage: "gearshape") { openDashboard(.settings) }
                Button("用量历史", systemImage: "chart.xyaxis.line") { openDashboard(.history) }
                Divider()
                Button("退出 GPT 用量", systemImage: "power") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 20, height: 24)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("设置与更多操作").accessibilityLabel("设置与更多操作")
        }
        .foregroundStyle(.primary)
    }

    private func compactMetric(_ title: String, value: String, warning: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer(minLength: 2)
            Text(value).font(.system(size: 12, weight: .medium)).monospacedDigit()
                .foregroundStyle(warning ? Color.orange : Color.primary).lineLimit(1)
        }
    }

    private func shortCountdown(to date: Date?, now: Date) -> String {
        guard let date else { return "—" }
        if date <= now { return "即将重置" }
        return DisplayFormat.countdown(to: date, now: now)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "小时", with: "时")
            .replacingOccurrences(of: "分钟", with: "分")
    }

    private func availability(now: Date) -> String {
        guard hasCurrentData, let remaining = model.remainingPercent else { return "—" }
        if remaining == 0 { return "已用尽" }
        guard let forecast = model.forecast else { return "—" }
        if !forecast.exhaustsBeforeReset { return "至重置" }
        if forecast.exhaustedAt <= now { return "即将用尽" }
        return shortCountdown(to: forecast.exhaustedAt, now: now)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(model.lastError != nil ? Color.orange : (hasCurrentData ? Color.green : Color.secondary))
                .frame(width: 4, height: 4).accessibilityHidden(true)
            Text(updateLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                .help(model.refreshText).accessibilityLabel(model.refreshText)
            Spacer()
            Button { openDashboard(.overview) } label: {
                HStack(spacing: 4) {
                    Text("详情")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
        }
    }

    private var updateLabel: String {
        if model.isRefreshing { return "更新中" }
        if model.lastError != nil { return model.snapshot == nil ? "读取失败" : "更新失败 · 缓存" }
        guard let date = model.snapshot?.fetchedAt else { return "等待数据" }
        if model.dataIsStale { return "缓存数据" }
        return date.formatted(.dateTime.hour().minute()) + " 更新"
    }

    private func openDashboard(_ tab: DashboardTab) {
        model.dashboardTab = tab
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "dashboard")
    }
}

struct WeeklyPercentChart: View {
    let points: [DailyPercentPoint]
    var openHistory: (() -> Void)? = nil
    private let plotHeight: CGFloat = 48
    private var scaleMaximum: Double { max(10, points.compactMap(\.value).max() ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("每日消耗").font(.system(size: 11, weight: .medium))
                Text("近 7 天").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if let openHistory {
                    Button(action: openHistory) { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)) }
                        .buttonStyle(.borderless).accessibilityLabel("用量历史")
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(points) { point in
                    let today = Calendar.current.isDateInToday(point.date)
                    VStack(spacing: 5) {
                        Text(DisplayFormat.percent(point.value))
                            .font(.system(size: 10, weight: today ? .semibold : .regular))
                            .foregroundStyle(today ? Color.accentColor : Color.secondary).monospacedDigit()
                        ZStack(alignment: .bottom) {
                            if let value = point.value {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.accentColor.opacity(today ? 1 : 0.28))
                                    .frame(height: max(2, plotHeight * CGFloat(max(0, value) / scaleMaximum)))
                            } else {
                                Capsule().fill(.secondary.opacity(0.2)).frame(width: 7, height: 2)
                            }
                        }
                        .frame(width: 19, height: plotHeight, alignment: .bottom)
                        Text(today ? "今天" : point.date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                            .font(.system(size: 9)).foregroundStyle(today ? Color.primary : Color.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(DisplayFormat.day.string(from: point.date)) · \(point.value.map { DisplayFormat.percent($0) } ?? "未记录")")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(DisplayFormat.day.string(from: point.date))，\(point.value.map { "消耗 \(DisplayFormat.percent($0))" } ?? "未记录")")
                }
            }
        }
        .help("本地观测的配额消耗；— 表示未记录。")
    }
}
