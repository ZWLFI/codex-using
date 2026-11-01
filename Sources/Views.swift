import AppKit
import Combine
import SwiftUI

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
    @State private var statusDate = Date()
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        // TimelineView inside a MenuBarExtra label can repeatedly invalidate its host.
        Image(nsImage: StatusItemArtwork.image(
            style: settings.menuStyle,
            remaining: model.remainingPercent,
            resetDate: model.selectedWindow?.resetDate
        ))
        .interpolation(.high)
        .frame(height: 22)
        .accessibilityLabel(statusDescription)
        .help(statusDescription)
        .onReceive(clock) { statusDate = $0 }
        .onAppear {
            model.start()
            if CommandLine.arguments.contains("--show-dashboard") {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private var statusDescription: String {
        let state = QuotaDataState.resolve(fetchedAt: model.snapshot?.fetchedAt,
                                          resetDate: model.selectedWindow?.resetDate,
                                          hasError: model.lastError != nil, now: statusDate)
        let status = state == .current ? model.risk.title : state.title
        return "GPT 用量，剩余 \(DisplayFormat.percent(model.remainingPercent))，\(status)"
    }
}
