import SwiftUI

/// Loading screen shown at launch: rows of glowing wire hangers on a dark
/// CRT screen, drifting slowly sideways, with the wardrobe's name box.
struct HangerLaunchView: View {
    /// Size of one hanger tile.
    var tile = CGSize(width: 92, height: 78)

    var body: some View {
        ZStack {
            Color("LaunchBackground")

            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    drawHangers(in: &context, size: size, time: time)
                }
            }

            VStack(spacing: 6) {
                Text("WangSwipe's Wardrobe")
                    .font(Retro.font(18))
                TimelineView(.periodic(from: .now, by: 0.4)) { timeline in
                    let dots = Int(timeline.date.timeIntervalSinceReferenceDate / 0.4) % 4
                    Text("Loading" + String(repeating: ".", count: dots))
                        .font(Retro.font(12, weight: .bold))
                        .frame(width: 120, alignment: .leading)
                        .padding(.leading, 24)
                }
            }
            .textCase(.uppercase)
            .foregroundStyle(Retro.lavender)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Retro.navy)
            .overlay(Rectangle().stroke(Retro.lavender, lineWidth: 2))
            .shadow(color: Retro.lavender.opacity(0.5), radius: 10)
        }
        .overlay(Scanlines())
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading WangSwipe's Wardrobe")
    }

    private func drawHangers(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let drift = CGFloat(time.truncatingRemainder(dividingBy: 60) * 10)
        let rows = Int(ceil(size.height / tile.height)) + 1
        let columns = Int(ceil(size.width / tile.width)) + 2

        var wires = Path()
        for row in 0..<rows {
            // Alternate rows drift opposite ways and sit half a tile apart.
            let direction: CGFloat = row.isMultiple(of: 2) ? 1 : -1
            let stagger: CGFloat = row.isMultiple(of: 2) ? 0 : tile.width / 2
            let shift = (drift * direction + stagger).truncatingRemainder(dividingBy: tile.width)
            for column in -1..<columns {
                let origin = CGPoint(
                    x: CGFloat(column) * tile.width + shift,
                    y: CGFloat(row) * tile.height + 8
                )
                wires.addPath(Self.hanger(in: CGRect(origin: origin, size: CGSize(width: tile.width - 18, height: tile.height - 22))))
            }
        }

        let style = StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
        // Soft glow underneath, then the crisp wire.
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 4))
            glow.stroke(wires, with: .color(Retro.periwinkle.opacity(0.9)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        context.stroke(wires, with: .color(Color.white.opacity(0.92)), style: style)
    }

    /// One wire hanger: a curled hook, a twisted neck and a triangular body.
    static func hanger(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        // Hook: up from the neck, over the top, curling back down.
        path.move(to: p(0.5, 0.34))
        path.addLine(to: p(0.5, 0.2))
        path.addCurve(to: p(0.41, 0.02), control1: p(0.5, 0.08), control2: p(0.47, 0.02))
        path.addCurve(to: p(0.33, 0.14), control1: p(0.35, 0.02), control2: p(0.32, 0.07))
        // Twist at the neck.
        path.move(to: p(0.47, 0.30))
        path.addLine(to: p(0.53, 0.36))
        path.move(to: p(0.47, 0.36))
        path.addLine(to: p(0.53, 0.40))
        // Shoulders and the bottom bar.
        path.move(to: p(0.5, 0.38))
        path.addQuadCurve(to: p(0.03, 0.9), control: p(0.22, 0.6))
        path.addQuadCurve(to: p(0.08, 0.98), control: p(0.0, 0.97))
        path.addLine(to: p(0.92, 0.98))
        path.addQuadCurve(to: p(0.97, 0.9), control: p(1.0, 0.97))
        path.addQuadCurve(to: p(0.5, 0.38), control: p(0.78, 0.6))
        return path
    }
}

#Preview {
    HangerLaunchView()
}
