import Charts
import SwiftUI

// Keep gaps as gaps: selecting a date must never snap to a neighbouring record.
enum UsageChartSelection {
    static func point(on date: Date, in points: [DayPoint], calendar: Calendar = .current) -> DayPoint? {
        points.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    static func domain(for points: [DayPoint], calendar: Calendar = .current) -> ClosedRange<Date>? {
        guard let first = points.map(\.date).min(), let last = points.map(\.date).max(),
              let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) else { return nil }
        return calendar.startOfDay(for: first)...end
    }

    static func plotX(at location: CGPoint, in frame: CGRect) -> CGFloat? {
        guard frame.width > 0, frame.height > 0,
              location.x >= frame.minX, location.x < frame.maxX,
              location.y >= frame.minY, location.y < frame.maxY else { return nil }
        return location.x - frame.minX
    }
}

struct HistoryChart: View {
    let points: [DayPoint]
    let title: String
    var height: CGFloat = 145
    @State private var inspectedDay: Date?

    private var available: [DayPoint] { points.filter { $0.tokens != nil } }
    private var selectedPoint: DayPoint? {
        inspectedDay.flatMap { UsageChartSelection.point(on: $0, in: points) }
    }
    private var domain: ClosedRange<Date> {
        UsageChartSelection.domain(for: points) ?? Date()...Date()
    }
    private var selectedMidday: Date? {
        guard let day = inspectedDay,
              let next = Calendar.current.date(byAdding: .day, value: 1, to: day) else { return nil }
        return day.addingTimeInterval(next.timeIntervalSince(day) / 2)
    }
    private var summary: String {
        if let day = inspectedDay {
            let value = selectedPoint?.tokens.map { "\($0.formatted()) token" } ?? "未记录"
            return "\(DisplayFormat.day.string(from: day)) · \(value)"
        }
        return available.max(by: { $0.date < $1.date }).map { "截至 \(DisplayFormat.day.string(from: $0.date))" } ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 12)
                Text(summary)
                    .font(.system(size: 10)).monospacedDigit().lineLimit(1)
                    .foregroundStyle(inspectedDay == nil ? Color.secondary : Color.primary)
            }
            if available.isEmpty {
                Label("暂无历史记录", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).frame(height: height)
            } else {
                Chart {
                    ForEach(available) { point in
                        BarMark(
                            x: .value("日期", point.date, unit: .day),
                            y: .value("Token", point.tokens ?? 0)
                        )
                        .foregroundStyle(Color.accentColor.opacity(barOpacity(for: point)))
                        .cornerRadius(2)
                        .accessibilityLabel(DisplayFormat.day.string(from: point.date))
                        .accessibilityValue("\(point.tokens ?? 0) token")
                    }
                    if let date = selectedMidday {
                        RuleMark(x: .value("查看日期", date))
                            .foregroundStyle(Color.secondary.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 0.7))
                            .accessibilityHidden(true)
                    }
                }
                .chartXScale(domain: domain)
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
                    AxisMarks(values: .automatic(desiredCount: min(7, max(2, points.count)))) { value in
                        AxisValueLabel(anchor: value.index == value.count - 1 ? .topTrailing : .topLeading) {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.month().day()).fixedSize()
                            }
                        }
                    }
                }
                .chartPlotStyle { plot in plot.padding(.top, 4) }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location): inspect(location, proxy: proxy, geometry: geometry)
                                case .ended: inspectedDay = nil
                                }
                            }
                            .gesture(SpatialTapGesture().onEnded { event in
                                inspect(event.location, proxy: proxy, geometry: geometry)
                            })
                            .accessibilityHidden(true)
                    }
                }
                .frame(height: height)
                .accessibilityLabel("\(title)图表")
            }
        }
        .onChange(of: points) { _ in inspectedDay = nil }
    }

    private func barOpacity(for point: DayPoint) -> Double {
        guard inspectedDay != nil else { return 0.75 }
        return selectedPoint?.id == point.id ? 1 : 0.35
    }

    private func inspect(_ location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        let frame = geometry[proxy.plotAreaFrame]
        guard let x = UsageChartSelection.plotX(at: location, in: frame),
              let date = proxy.value(atX: x, as: Date.self) else {
            inspectedDay = nil
            return
        }
        let day = Calendar.current.startOfDay(for: date)
        inspectedDay = day >= domain.lowerBound && day < domain.upperBound ? day : nil
    }
}
