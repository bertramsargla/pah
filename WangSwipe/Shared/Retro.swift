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
        .background(Retro.navy.ignoresSafeArea(edges: .top))
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

/// Procedural leopard print: tan ground, brown rosettes with broken dark rims.
/// Seeded, so it looks the same every time.
struct LeopardPattern: View {
    var tile: CGFloat = 120

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Retro.tan))
            let columns = Int(ceil(size.width / tile)) + 1
            let rows = Int(ceil(size.height / tile)) + 1
            for row in 0..<rows {
                for column in 0..<columns {
                    var rng = SeededRandom(seed: UInt64(row &* 7919 &+ column &* 104_729 &+ 17))
                    for _ in 0..<5 {
                        let center = CGPoint(
                            x: (CGFloat(column) + rng.next()) * tile,
                            y: (CGFloat(row) + rng.next()) * tile
                        )
                        let w = 18 + rng.next() * 16
                        let h = 14 + rng.next() * 12
                        let rect = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
                        let angle = Angle.degrees(Double(rng.next()) * 180)
                        let transform = CGAffineTransform(translationX: center.x, y: center.y)
                            .rotated(by: CGFloat(angle.radians))
                            .translatedBy(x: -center.x, y: -center.y)
                        let shape = Path(ellipseIn: rect).applying(transform)
                        context.fill(shape, with: .color(Retro.spot))
                        context.stroke(
                            shape,
                            with: .color(Retro.spotRim),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [9 + rng.next() * 6, 5 + rng.next() * 4])
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
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
