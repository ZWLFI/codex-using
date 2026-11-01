import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var hasCurrentData: Bool { model.dataState == .current }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 14) {
                header
                QuotaGauge(value: model.remainingPercent, isCurrent: hasCurrentData)
                quotaSummary(now: context.date)
                    .padding(.horizontal, 2)
                WeeklyPercentChart(points: model.dailyPercentPoints7) { openDashboard(.history) }
                    .padding(.horizontal, 2)
                footer
            }
            .padding(16)
        }
        .frame(width: 368)
        .background(UITheme.shell)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .tint(UITheme.accent)
    }

    private func quotaSummary(now: Date) -> some View {
        VStack(spacing: 10) {
            compactMetric("重置时间", value: shortCountdown(to: model.selectedWindow?.resetDate, now: now))
                .help(model.selectedWindow?.resetDate.map { DisplayFormat.dateTime.string(from: $0) } ?? "暂无重置时间")
            compactMetric("预计可用", value: availability(now: now), warning: hasCurrentData && model.risk == .critical)
                .help(!hasCurrentData ? "更新后显示预测" : model.remainingPercent == 0 ? "配额已用尽，等待重置" : model.forecastText)
        }
        .padding(.bottom, 2)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.medium")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 30, height: 30)
                .background(UITheme.shell, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
                .accessibilityHidden(true)
            if model.buckets.count > 1 {
                Menu {
                    Picker("配额", selection: Binding(
                        get: { model.selectedBucket?.id ?? "" }, set: model.selectBucket
                    )) {
                        ForEach(model.buckets) { bucket in Text(bucket.displayName).tag(bucket.id) }
                    }
                } label: {
                    Text(model.selectedBucket?.displayName ?? "Codex")
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("选择配额")
                .help(model.selectedBucket?.displayName ?? "选择配额")
            } else {
                Text(model.selectedBucket?.displayName ?? "Codex")
                    .font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            if let bucket = model.selectedBucket {
                Text(bucket.planName)
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(UITheme.secondaryText)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.primary.opacity(0.06), in: Capsule())
            }
            Spacer(minLength: 4)
            Button(action: model.refresh) {
                ZStack {
                    Image(systemName: "arrow.clockwise").opacity(model.isRefreshing ? 0 : 1)
                    if model.isRefreshing { ProgressView().controlSize(.mini) }
                }
                .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.borderless).disabled(model.isRefreshing)
            .keyboardShortcut("r", modifiers: .command)
            .help("刷新 ⌘R").accessibilityLabel(model.isRefreshing ? "正在刷新" : "刷新用量")
            Menu {
                Button("设置…", systemImage: "gearshape") { openDashboard(.settings) }
                Button("用量历史", systemImage: "chart.xyaxis.line") { openDashboard(.history) }
                Divider()
                Button("退出 GPT 用量", systemImage: "power") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("设置与更多操作").accessibilityLabel("设置与更多操作")
        }
        .foregroundStyle(.primary)
    }

    private func compactMetric(_ title: String, value: String, warning: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.system(size: 12)).foregroundStyle(UITheme.secondaryText)
            Spacer(minLength: 2)
            Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit()
                .foregroundStyle(warning ? UITheme.warning : Color.primary)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .combine)
    }

    private func shortCountdown(to date: Date?, now: Date) -> String {
        guard let date else { return "—" }
        if date <= now { return "等待更新" }
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
        HStack(spacing: 6) {
            Image(systemName: model.lastError != nil ? "exclamationmark.circle" : "clock")
                .foregroundStyle(model.lastError != nil ? UITheme.warning : UITheme.secondaryText)
                .accessibilityHidden(true)
            Text(updateLabel).font(UITheme.caption).foregroundStyle(UITheme.secondaryText)
                .lineLimit(1).help(statusHelp).accessibilityLabel(statusHelp)
            Spacer(minLength: 8)
            Button { openDashboard(.overview) } label: {
                HStack(spacing: 5) {
                    Text("打开详情")
                    Image(systemName: "arrow.up.right").accessibilityHidden(true)
                }
                .font(.system(size: 11, weight: .medium))
                .frame(minHeight: 28).contentShape(Rectangle())
            }
            .buttonStyle(.borderless).foregroundStyle(UITheme.accent)
        }
    }

    private var updateLabel: String {
        if model.isRefreshing { return "更新中" }
        if model.lastError != nil { return model.snapshot == nil ? "读取失败" : "更新失败 · 缓存" }
        guard let date = model.snapshot?.fetchedAt else { return "等待数据" }
        if model.dataState != .current { return model.dataState.title }
        return date.formatted(.dateTime.hour().minute()) + " 更新"
    }

    private var statusHelp: String {
        if let error = model.lastError { return "\(updateLabel)：\(error)" }
        guard let date = model.snapshot?.fetchedAt else { return updateLabel }
        return "\(updateLabel)，上次读取 \(DisplayFormat.dateTime.string(from: date))"
    }

    private func openDashboard(_ tab: DashboardTab) {
        model.dashboardTab = tab
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct WeeklyPercentChart: View {
    let points: [DailyPercentPoint]
    var openHistory: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredKey: String?
    private let plotHeight: CGFloat = 56
    private var scaleMaximum: Double { max(100, points.compactMap(\.value).max() ?? 0) }
    private var inspectedPoint: DailyPercentPoint? {
        points.first { $0.key == hoveredKey } ?? points.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let openHistory {
                Button(action: openHistory) {
                    HStack {
                        Text("近 7 天消耗").font(UITheme.section)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(UITheme.secondaryText).accessibilityHidden(true)
                    }
                    .frame(minHeight: 28).contentShape(Rectangle())
                }
                .buttonStyle(.borderless).foregroundStyle(.primary)
                .accessibilityLabel("近 7 天消耗，查看历史")
                .help("本地观测的配额消耗；— 表示未记录。柱图满格 \(DisplayFormat.observedPercent(scaleMaximum))。点击查看历史。")
            } else {
                Text("近 7 天消耗").font(UITheme.section).frame(minHeight: 28)
            }
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(points) { point in
                    let today = Calendar.current.isDateInToday(point.date)
                    let selected = point.key == inspectedPoint?.key
                    VStack(spacing: 8) {
                        Text(DisplayFormat.observedPercent(point.value))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selected ? UITheme.accent : Color.primary)
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                            .frame(height: 16)
                        ZStack(alignment: .bottom) {
                            if let value = point.value {
                                VStack(spacing: 2) {
                                    ForEach((0..<10).reversed(), id: \.self) { segment in
                                        let fill = max(0, min(1, value / scaleMaximum * 10 - Double(segment)))
                                        ZStack(alignment: .bottom) {
                                            RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.06))
                                            RoundedRectangle(cornerRadius: 1)
                                                .fill(UITheme.accent.opacity(selected ? 1 : 0.58))
                                                .frame(height: 3.8 * fill)
                                        }
                                        .frame(height: 3.8)
                                    }
                                }
                                .shadow(color: selected ? UITheme.accent.opacity(0.22) : .clear, radius: 3)
                            } else {
                                Capsule().fill(.secondary.opacity(0.5)).frame(width: 9, height: 2)
                            }
                        }
                        .frame(width: 23, height: plotHeight, alignment: .bottom)
                        Text(today ? "今天" : point.date.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                            .font(UITheme.caption)
                            .foregroundStyle(selected ? UITheme.accent : UITheme.secondaryText)
                            .frame(maxWidth: .infinity).frame(height: 22)
                            .background(selected ? UITheme.accent.opacity(0.10) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { hoveredKey = point.key }
                        else if hoveredKey == point.key { hoveredKey = nil }
                    }
                    .help("\(DisplayFormat.day.string(from: point.date)) · \(point.value.map { DisplayFormat.observedPercent($0) } ?? "未记录")")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(DisplayFormat.day.string(from: point.date))，\(point.value.map { "消耗 \(DisplayFormat.observedPercent($0))" } ?? "未记录")")
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredKey)
        }
        .onChange(of: points) { _ in hoveredKey = nil }
    }
}
