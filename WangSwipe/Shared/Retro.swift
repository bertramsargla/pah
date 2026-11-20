import SwiftUI

/// The app's look: an early-90s "virtual wardrobe" computer. Navy title bars,
/// periwinkle panels, beveled buttons, leopard print and chunky monospaced type.
enum Retro {
    static let navy = Color(red: 0.11, green: 0.12, blue: 0.29)
    static let navyLight = Color(red: 0.20, green: 0.22, blue: 0.45)
    static let lavender = Color(red: 0.78, green: 0.81, blue: 0.96)
    static let periwinkle = Color(red: 0.69, green: 0.74, blue: 0.94)
    static let buttonGray = Color(red: 0.62, green: 0.66, blue: 0.82)
    static let electricBlue = Color(red: 0.25, green: 0.35, blue: 0.92)
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.20)
    static let tan = Color(red: 0.86, green: 0.77, blue: 0.66)
    static let spot = Color(red: 0.62, green: 0.40, blue: 0.27)
    static let spotRim = Color(red: 0.33, green: 0.20, blue: 0.14)

    static func font(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Bevel

/// Classic raised (or sunken) 3D edge: light on top/left, dark on bottom/right.
struct Bevel: View {
    var raised = true
    var width: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, i = width / 2
            let light = Color.white.opacity(0.85)
            let dark = Color.black.opacity(0.55)
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: i, y: h - i))
                    p.addLine(to: CGPoint(x: i, y: i))
                    p.addLine(to: CGPoint(x: w - i, y: i))
                }
                .stroke(raised ? light : dark, lineWidth: width)
                Path { p in
                    p.move(to: CGPoint(x: w - i, y: i))
                    p.addLine(to: CGPoint(x: w - i, y: h - i))
                    p.addLine(to: CGPoint(x: i, y: h - i))
                }
                .stroke(raised ? dark : light, lineWidth: width)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Chunky beveled button. Presses in when tapped.
struct BevelButtonStyle: ButtonStyle {
    var fill: Color = Retro.buttonGray
    var text: Color = Retro.ink
    var size: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Retro.font(size))
            .textCase(.uppercase)
            .foregroundStyle(text)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? fill.opacity(0.8) : fill)
            .overlay(Bevel(raised: !configuration.isPressed, width: 4))
            .overlay(Rectangle().stroke(Retro.ink, lineWidth: 1.5))
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

extension ButtonStyle where Self == BevelButtonStyle {
    static var bevel: BevelButtonStyle { BevelButtonStyle() }
    static var bevelPrimary: BevelButtonStyle {
        BevelButtonStyle(fill: Retro.electricBlue, text: Retro.lavender, size: 22)
    }
}

// MARK: - Panels and bars

/// Sunken periwinkle panel, like the wardrobe's display windows.
struct RetroPanel<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Retro.lavender)
            .overlay(Bevel(raised: false, width: 4))
            .overlay(Rectangle().stroke(Retro.ink, lineWidth: 2))
    }
}

/// Navy title strip: app name on the left, a boxed screen name in the middle.
struct RetroTitleBar: View {
    var left = "WangSwipe's Wardrobe"
    var title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(left)
                .font(Retro.font(12, weight: .bold))
                .foregroundStyle(Retro.lavender.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Text(title)
                .font(Retro.font(15))
                .foregroundStyle(Retro.lavender)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .overlay(Rectangle().stroke(Retro.lavender, lineWidth: 1.5))
        }
        .textCase(.uppercase)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Retro.navy, ignoresSafeAreaEdges: [])
        // The status bar sits on lavender so its dark text stays readable.
        .background(Retro.lavender.ignoresSafeArea(edges: .top))
    }
}

/// Faint CRT scanlines laid over a screen.
struct Scanlines: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.07)))
                y += 3
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Leopard print

/// Procedural leopard print: tan ground, rosettes made of a warm brown center
/// ringed by broken dark blobs, plus small solid spots. Seeded, so it looks
/// the same every time.
struct LeopardPattern: View {
    var tile: CGFloat = 110

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Retro.tan))
            let columns = Int(ceil(size.width / tile)) + 1
            let rows = Int(ceil(size.height / tile)) + 1
            for row in 0..<rows {
                for column in 0..<columns {
                    var rng = SeededRandom(seed: UInt64(row &* 7919 &+ column &* 104_729 &+ 17))
                    // Two rosettes per tile, jittered.
                    for slot in 0..<2 {
                        let center = CGPoint(
                            x: (CGFloat(column) + CGFloat(slot) * 0.5 + rng.next() * 0.35) * tile,
                            y: (CGFloat(row) + CGFloat(slot) * 0.5 + rng.next() * 0.35) * tile
                        )
                        Self.rosette(in: &context, at: center, radius: 14 + rng.next() * 8, rng: &rng)
                    }
                    // A few small solid spots between rosettes.
                    for _ in 0..<3 {
                        let point = CGPoint(
                            x: (CGFloat(column) + rng.next()) * tile,
                            y: (CGFloat(row) + rng.next()) * tile
                        )
                        let r = 2.5 + rng.next() * 3
                        context.fill(
                            Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r * 0.8, width: r * 2, height: r * 1.6)),
                            with: .color(Retro.spotRim)
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private static func rosette(in context: inout GraphicsContext, at center: CGPoint, radius: CGFloat, rng: inout SeededRandom) {
        // Warm center, slightly irregular.
        let inner = CGRect(
            x: center.x - radius * 0.8, y: center.y - radius * 0.65,
            width: radius * 1.6, height: radius * 1.3
        )
        context.fill(Path(ellipseIn: inner), with: .color(Retro.spot))

        // 4-6 dark blobs around the edge, with gaps between them.
        let blobs = 4 + Int(rng.next() * 3)
        let start = rng.next() * .pi * 2
        for index in 0..<blobs {
            let angle = start + CGFloat(index) / CGFloat(blobs) * .pi * 2 + (rng.next() - 0.5) * 0.4
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius * 0.85)
            let length = radius * (0.55 + rng.next() * 0.35)
            let thickness = radius * (0.28 + rng.next() * 0.15)
            let blob = Path(roundedRect: CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness),
                            cornerRadius: thickness / 2)
                .applying(CGAffineTransform(rotationAngle: angle + .pi / 2))
                .applying(CGAffineTransform(translationX: point.x, y: point.y))
            context.fill(blob, with: .color(Retro.spotRim))
        }
    }
}

/// Small deterministic random generator (SplitMix64) for the pattern.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    /// Returns a value in 0..<1.
    mutating func next() -> CGFloat {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return CGFloat(z >> 11) / CGFloat(1 << 53)
    }
}
