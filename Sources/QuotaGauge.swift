import SwiftUI

struct QuotaGauge: View {
    let value: Double?
    var isCurrent: Bool = true
    var height: CGFloat = 204

    private var reading: Double? {
        guard let value, value.isFinite else { return nil }
        return max(0, min(100, value))
    }
    private var tint: Color { isCurrent && reading != nil ? UITheme.accent : UITheme.secondaryText }

    var body: some View {
        GeometryReader { geometry in
            let digitHeight = min(42, geometry.size.height * 0.19)
            let readout = reading.map { String(Int($0.rounded())) }
            // A seven-segment 1 has an empty left edge; center the visible digits.
            let leadingInset = readout?.hasPrefix("1") == true ? digitHeight * 0.59 * 0.83 : 0
            ZStack {
                LinearGradient(
                    colors: [Color(white: 0.075), Color(white: 0.045)],
                    startPoint: .top, endPoint: .bottom
                )
                RadialGradient(
                    stops: [.init(color: tint.opacity(isCurrent ? 0.15 : 0.025), location: 0),
                            .init(color: tint.opacity(isCurrent ? 0.06 : 0.01), location: 0.65),
                            .init(color: .clear, location: 1)],
                    center: .init(x: 0.5, y: 0.35), startRadius: 8, endRadius: geometry.size.width * 0.65
                )
                LinearGradient(
                    stops: [.init(color: .white.opacity(0.045), location: 0),
                            .init(color: .clear, location: 0.48)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                HStack(spacing: 4) {
                    if let readout {
                        ForEach(Array(readout.enumerated()), id: \.offset) { _, character in
                            if let digit = character.wholeNumberValue {
                                GaugeDigit(digit: digit)
                                    .fill(tint)
                                    .frame(width: digitHeight * 0.59, height: digitHeight)
                                    .shadow(color: tint.opacity(isCurrent ? 0.22 : 0), radius: 3)
                            }
                        }
                    } else {
                        Text("—")
                            .font(.system(size: digitHeight, weight: .light, design: .monospaced))
                            .foregroundStyle(tint)
                            .frame(height: digitHeight)
                    }
                }
                .fixedSize()
                .position(x: geometry.size.width / 2 - leadingInset / 2, y: geometry.size.height * 0.60)
                .accessibilityHidden(true)

                Canvas { context, size in
                    // The centered readout sits beneath the physical needle, without an opaque mask.
                    let center = CGPoint(x: size.width / 2, y: size.height * 0.95)
                    let radius = min(size.width * 0.43, size.height * 0.74)
                    let start = -146.0
                    let sweep = 112.0

                    func position(_ angle: Double, _ distance: CGFloat) -> CGPoint {
                        let radians: Double = angle * Double.pi / 180
                        return CGPoint(x: center.x + CGFloat(cos(radians)) * distance, y: center.y + CGFloat(sin(radians)) * distance)
                    }
                    func arc(to angle: Double, radius: CGFloat) -> Path {
                        Path { path in
                            path.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(angle), clockwise: false)
                        }
                    }

                    context.stroke(arc(to: start + sweep, radius: radius - 2), with: .color(.black.opacity(0.85)), lineWidth: 6)
                    context.stroke(arc(to: start + sweep, radius: radius), with: .color(tint.opacity(0.35)), lineWidth: 0.7)
                    context.stroke(arc(to: start + sweep, radius: radius - 2), with: .color(tint.opacity(0.28)), lineWidth: 2)
                    context.stroke(arc(to: start + sweep, radius: radius - 5), with: .color(tint.opacity(0.14)), lineWidth: 0.7)

                    if let reading, reading > 0 {
                        var glow = context
                        glow.addFilter(.shadow(color: tint.opacity(0.40), radius: 4))
                        glow.stroke(
                            arc(to: start + sweep * reading / 100, radius: radius - 2),
                            with: .color(tint.opacity(isCurrent ? 0.9 : 0.5)),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                        )
                    }

                    var backlight = context
                    backlight.addFilter(.shadow(color: tint.opacity(isCurrent ? 0.25 : 0), radius: 1.3))
                    for tick in 0...40 {
                        let angle = start + sweep * Double(tick) / 40
                        let major = tick.isMultiple(of: 10)
                        let middle = tick.isMultiple(of: 5)
                        let length: CGFloat = major ? 10 : middle ? 7 : 4
                        var mark = Path()
                        mark.move(to: position(angle, radius + 2))
                        mark.addLine(to: position(angle, radius + 2 + length))
                        var engraving = context
                        engraving.translateBy(x: 0, y: 1)
                        engraving.stroke(mark, with: .color(.black.opacity(0.85)), lineWidth: major ? 2 : 1.5)
                        backlight.stroke(mark, with: .color(tint.opacity(major ? 0.95 : 0.6)), lineWidth: major ? 1.2 : 0.8)

                        if major {
                            backlight.draw(
                                Text("\(tick * 5 / 2)")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(tint.opacity(0.92)),
                                at: position(angle, radius + 22)
                            )
                        }
                    }

                    if let reading {
                        let angle = start + sweep * reading / 100
                        let radians = angle * .pi / 180
                        let normal = CGVector(dx: -sin(radians), dy: cos(radians))
                        let tip = position(angle, radius + 10)
                        let tail = position(angle, -6)
                        let left = CGPoint(x: tail.x + normal.dx * 3, y: tail.y + normal.dy * 3)
                        let right = CGPoint(x: tail.x - normal.dx * 3, y: tail.y - normal.dy * 3)
                        var needle = Path()
                        needle.addLines([tip, left, right])
                        needle.closeSubpath()
                        var metal = context
                        metal.opacity = isCurrent ? 1 : 0.6
                        metal.addFilter(.shadow(color: .black.opacity(0.9), radius: 2, x: 1.5, y: 2.5))
                        metal.fill(needle, with: .linearGradient(
                            Gradient(colors: [Color(white: 0.90), Color(white: 0.64), Color(white: 0.24)]),
                            startPoint: left, endPoint: right
                        ))
                        context.stroke(needle, with: .color(.white.opacity(isCurrent ? 0.32 : 0.16)), lineWidth: 0.5)
                        var bevel = Path()
                        bevel.move(to: left)
                        bevel.addLine(to: tip)
                        context.stroke(bevel, with: .color(.white.opacity(isCurrent ? 0.8 : 0.35)), lineWidth: 0.6)
                    }

                    let hubRadius = min(11, size.height * 0.052)
                    let pivot = CGRect(x: center.x - hubRadius, y: center.y - hubRadius, width: hubRadius * 2, height: hubRadius * 2)
                    var hub = context
                    hub.addFilter(.shadow(color: .black.opacity(0.85), radius: 2.5, x: 0, y: 2))
                    hub.fill(Path(ellipseIn: pivot), with: .linearGradient(
                        Gradient(colors: [Color(white: 0.66), Color(white: 0.22), Color(white: 0.10), Color(white: 0.40)]),
                        startPoint: CGPoint(x: pivot.minX, y: pivot.minY),
                        endPoint: CGPoint(x: pivot.maxX, y: pivot.maxY)
                    ))
                    context.stroke(Path(ellipseIn: pivot), with: .color(.white.opacity(0.24)), lineWidth: 0.5)
                    let cap = pivot.insetBy(dx: 2.3, dy: 2.3)
                    context.fill(Path(ellipseIn: cap), with: .radialGradient(
                        Gradient(colors: [Color(white: 0.34), Color(white: 0.14), Color(white: 0.065)]),
                        center: CGPoint(x: center.x - 2, y: center.y - 3), startRadius: 0, endRadius: hubRadius
                    ))
                    context.stroke(Path(ellipseIn: cap), with: .color(.black.opacity(0.8)), lineWidth: 0.6)
                }
                .accessibilityHidden(true)

                VStack {
                    HStack {
                        Text("剩余配额")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(UITheme.secondaryText)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(14)
                .accessibilityHidden(true)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.black.opacity(0.75), lineWidth: 2)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            LinearGradient(colors: [.black.opacity(0.65), .white.opacity(0.10)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.7
                        )
                }
                .allowsHitTesting(false).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("剩余配额")
        .accessibilityValue(reading.map { "\(Int($0.rounded()))%\(isCurrent ? "" : "，缓存数据")" } ?? "暂无数据")
    }
}

private struct GaugeDigit: Shape {
    let digit: Int
    private let masks = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F]

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let thickness = width * 0.17
        let bevel = thickness / 2
        let left = thickness * 0.65
        let right = width - left

        func horizontal(_ y: CGFloat) -> [CGPoint] {
            [CGPoint(x: left + bevel, y: y), CGPoint(x: right - bevel, y: y),
             CGPoint(x: right, y: y + bevel), CGPoint(x: right - bevel, y: y + thickness),
             CGPoint(x: left + bevel, y: y + thickness), CGPoint(x: left, y: y + bevel)]
        }
        func vertical(_ x: CGFloat, from top: CGFloat, to bottom: CGFloat) -> [CGPoint] {
            [CGPoint(x: x + bevel, y: top), CGPoint(x: x + thickness, y: top + bevel),
             CGPoint(x: x + thickness, y: bottom - bevel), CGPoint(x: x + bevel, y: bottom),
             CGPoint(x: x, y: bottom - bevel), CGPoint(x: x, y: top + bevel)]
        }
        let upperTop = thickness * 0.7
        let upperBottom = height / 2 - thickness * 0.2
        let lowerTop = height / 2 + thickness * 0.2
        let lowerBottom = height - thickness * 0.7
        let segments = [
            horizontal(0), vertical(width - thickness, from: upperTop, to: upperBottom),
            vertical(width - thickness, from: lowerTop, to: lowerBottom), horizontal(height - thickness),
            vertical(0, from: lowerTop, to: lowerBottom), vertical(0, from: upperTop, to: upperBottom),
            horizontal((height - thickness) / 2)
        ]
        var path = Path()
        for (index, vertices) in segments.enumerated() where masks[digit] & (1 << index) != 0 {
            path.addLines(vertices.map { CGPoint(x: $0.x + rect.minX, y: $0.y + rect.minY) })
            path.closeSubpath()
        }
        return path
    }
}
