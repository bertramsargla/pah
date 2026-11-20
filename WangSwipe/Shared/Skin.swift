import SwiftUI

/// The app's swappable looks. Each one recolors the same screens and swaps the
/// pattern behind them; the layout and buttons stay the same.
enum Skin: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Lavender panels, navy bars and leopard print: a 1995 teen-movie wardrobe computer.
    case clueless
    /// Phosphor green on black with falling code, like a late-90s sci-fi hacker terminal.
    case matrix
    /// Rusty metal, blood red and hellfire, like an early-90s PC shooter.
    case doom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clueless: "Clueless (1995) Wang Meme"
        case .matrix: "The Matrix (1999)"
        case .doom: "Doom (1993)"
        }
    }

    /// The boxed name in the wardrobe's title bar.
    var wardrobeTitle: String {
        switch self {
        case .clueless: "Fall Fashions"
        case .matrix: "Construct"
        case .doom: "Armory"
        }
    }

    /// Dark skins switch the system UI (status bar, Setup form) to dark mode.
    var isDark: Bool { self != .clueless }

    var next: Skin {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// The skin the views draw with. Set by `AppModel` from the saved settings;
    /// the root view is rebuilt when it changes, so plain storage is enough.
    static var current: Skin = .clueless

    var palette: Palette {
        switch self {
        case .clueless:
            Palette(
                bar: Color(red: 0.11, green: 0.12, blue: 0.29),
                onBar: Color(red: 0.78, green: 0.81, blue: 0.96),
                panel: Color(red: 0.78, green: 0.81, blue: 0.96),
                panelAlt: Color(red: 0.69, green: 0.74, blue: 0.94),
                ink: Color(red: 0.08, green: 0.08, blue: 0.20),
                button: Color(red: 0.62, green: 0.66, blue: 0.82),
                onButton: Color(red: 0.08, green: 0.08, blue: 0.20),
                primary: Color(red: 0.25, green: 0.35, blue: 0.92),
                onPrimary: Color(red: 0.78, green: 0.81, blue: 0.96),
                bevelLight: .white.opacity(0.85),
                bevelDark: .black.opacity(0.55),
                statusBar: Color(red: 0.78, green: 0.81, blue: 0.96),
                tint: Color(red: 0.11, green: 0.12, blue: 0.29),
                launch: Color(red: 0.05, green: 0.06, blue: 0.18),
                hanger: .white.opacity(0.92),
                hangerGlow: Color(red: 0.69, green: 0.74, blue: 0.94)
            )
        case .matrix:
            Palette(
                bar: .black,
                onBar: Color(red: 0.22, green: 1.0, blue: 0.42),
                panel: Color(red: 0.01, green: 0.07, blue: 0.03),
                panelAlt: Color(red: 0.02, green: 0.12, blue: 0.05),
                ink: Color(red: 0.22, green: 1.0, blue: 0.42),
                button: Color(red: 0.03, green: 0.18, blue: 0.07),
                onButton: Color(red: 0.55, green: 1.0, blue: 0.62),
                primary: Color(red: 0.0, green: 0.75, blue: 0.27),
                onPrimary: .black,
                bevelLight: Color(red: 0.4, green: 1.0, blue: 0.5).opacity(0.7),
                bevelDark: .black.opacity(0.8),
                statusBar: .black,
                tint: Color(red: 0.22, green: 1.0, blue: 0.42),
                launch: .black,
                hanger: Color(red: 0.7, green: 1.0, blue: 0.75),
                hangerGlow: Color(red: 0.0, green: 0.9, blue: 0.3)
            )
        case .doom:
            Palette(
                bar: Color(red: 0.10, green: 0.05, blue: 0.04),
                onBar: Color(red: 1.0, green: 0.62, blue: 0.10),
                panel: Color(red: 0.54, green: 0.49, blue: 0.43),
                panelAlt: Color(red: 0.36, green: 0.31, blue: 0.27),
                ink: Color(red: 0.07, green: 0.04, blue: 0.03),
                button: Color(red: 0.36, green: 0.33, blue: 0.30),
                onButton: Color(red: 1.0, green: 0.80, blue: 0.35),
                primary: Color(red: 0.62, green: 0.05, blue: 0.04),
                onPrimary: Color(red: 1.0, green: 0.84, blue: 0.25),
                bevelLight: Color(red: 0.85, green: 0.78, blue: 0.68).opacity(0.85),
                bevelDark: .black.opacity(0.75),
                statusBar: Color(red: 0.10, green: 0.05, blue: 0.04),
                tint: Color(red: 1.0, green: 0.45, blue: 0.10),
                launch: Color(red: 0.06, green: 0.02, blue: 0.02),
                hanger: Color(red: 1.0, green: 0.78, blue: 0.40),
                hangerGlow: Color(red: 0.95, green: 0.20, blue: 0.05)
            )
        }
    }

    func font(_ size: CGFloat, weight: Font.Weight) -> Font {
        switch self {
        case .clueless:
            .system(size: size, weight: weight, design: .monospaced)
        case .matrix:
            .system(size: size, weight: weight == .heavy ? .bold : weight, design: .monospaced)
        case .doom:
            .system(size: size * 1.15, weight: .black, design: .default).width(.compressed).italic()
        }
    }

    /// Colors for every role a screen uses.
    struct Palette {
        /// Title bars, menu strips, captions.
        var bar: Color
        /// Text and outlines on `bar`.
        var onBar: Color
        /// Display panels.
        var panel: Color
        /// Secondary surfaces (loading areas, the mirror, Setup).
        var panelAlt: Color
        /// Text and outlines on panels.
        var ink: Color
        var button: Color
        var onButton: Color
        var primary: Color
        var onPrimary: Color
        var bevelLight: Color
        var bevelDark: Color
        /// Behind the status bar, chosen so its text stays readable.
        var statusBar: Color
        /// Tab bar and control tint.
        var tint: Color
        var launch: Color
        var hanger: Color
        var hangerGlow: Color
    }
}

/// The pattern behind each skin's screens.
struct SkinBackdrop: View {
    var body: some View {
        switch Skin.current {
        case .clueless: LeopardPattern()
        case .matrix: DigitalRain()
        case .doom: HellfireWall()
        }
    }
}

// MARK: - Matrix: falling code

/// Columns of green glyphs raining down, brightest at each column's head.
struct DigitalRain: View {
    var columnWidth: CGFloat = 16
    var animated = true

    private static let glyphs = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789:=*+-<>")

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !animated)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                let rowHeight = columnWidth * 1.1
                let rows = Int(size.height / rowHeight) + 2
                let columns = Int(size.width / columnWidth) + 1
                for column in 0..<columns {
                    var rng = SeededRandom(seed: UInt64(column &* 2_654_435_761 &+ 99))
                    let speed = 4 + rng.next() * 8          // rows per second
                    let trail = 8 + Int(rng.next() * 14)     // glyphs in the tail
                    let offset = rng.next() * 60
                    let cycle = CGFloat(rows + trail)
                    let head = Int((CGFloat(time) * speed + offset).truncatingRemainder(dividingBy: cycle))
                    for step in 0..<trail {
                        let row = head - step
                        guard row >= 0, row < rows else { continue }
                        // Glyphs flicker: pick by row and a slow clock.
                        let tick = Int(time * 3) % 100_000
                        var glyphRng = SeededRandom(seed: UInt64(column * 31 + row * 17 + tick * (step == 0 ? 7 : 1)))
                        let glyph = Self.glyphs[Int(glyphRng.next() * CGFloat(Self.glyphs.count))]
                        let fade = 1 - Double(step) / Double(trail)
                        let color: Color = step == 0
                            ? Color(red: 0.85, green: 1.0, blue: 0.88)
                            : Color(red: 0.1, green: 0.9, blue: 0.3).opacity(fade * 0.85)
                        let text = Text(String(glyph))
                            .font(.system(size: columnWidth * 0.9, weight: .medium, design: .monospaced))
                            .foregroundStyle(color)
                        context.draw(text, at: CGPoint(x: CGFloat(column) * columnWidth + columnWidth / 2,
                                                       y: CGFloat(row) * rowHeight))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Doom: riveted metal over hellfire

/// Rusty riveted metal plates with a flickering fire glow rising from below.
struct HellfireWall: View {
    var plate = CGSize(width: 64, height: 48)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                drawPlates(in: &context, size: size)
                drawFire(in: &context, size: size, time: time)
            }
        }
        .allowsHitTesting(false)
    }

    private func drawPlates(in context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.16, green: 0.10, blue: 0.08)))
        let rows = Int(size.height / plate.height) + 1
        let columns = Int(size.width / plate.width) + 2
        for row in 0..<rows {
            let shift: CGFloat = row.isMultiple(of: 2) ? 0 : -plate.width / 2
            for column in 0..<columns {
                var rng = SeededRandom(seed: UInt64(row &* 977 &+ column &* 61 &+ 5))
                let rect = CGRect(x: CGFloat(column) * plate.width + shift, y: CGFloat(row) * plate.height,
                                  width: plate.width, height: plate.height).insetBy(dx: 1, dy: 1)
                // Each plate a slightly different rusty brown-gray.
                let shade = 0.26 + rng.next() * 0.10
                let base = Color(red: shade + 0.08, green: shade * 0.82, blue: shade * 0.66)
                context.fill(Path(rect), with: .color(base))
                // Rust streaks.
                for _ in 0..<2 {
                    let x = rect.minX + rng.next() * rect.width
                    let streak = CGRect(x: x, y: rect.minY + rng.next() * 10, width: 2 + rng.next() * 3, height: rect.height * (0.3 + rng.next() * 0.5))
                    context.fill(Path(streak), with: .color(Color(red: 0.45, green: 0.18, blue: 0.08).opacity(0.5)))
                }
                // Bevel edges.
                var light = Path(); light.move(to: CGPoint(x: rect.minX, y: rect.maxY)); light.addLine(to: CGPoint(x: rect.minX, y: rect.minY)); light.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                var dark = Path(); dark.move(to: CGPoint(x: rect.maxX, y: rect.minY)); dark.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); dark.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                context.stroke(light, with: .color(.white.opacity(0.18)), lineWidth: 2)
                context.stroke(dark, with: .color(.black.opacity(0.6)), lineWidth: 2)
                // Rivets in the corners.
                for corner in [CGPoint(x: rect.minX + 6, y: rect.minY + 6), CGPoint(x: rect.maxX - 6, y: rect.minY + 6),
                               CGPoint(x: rect.minX + 6, y: rect.maxY - 6), CGPoint(x: rect.maxX - 6, y: rect.maxY - 6)] {
                    let r: CGFloat = 2.4
                    context.fill(Path(ellipseIn: CGRect(x: corner.x - r, y: corner.y - r, width: r * 2, height: r * 2)), with: .color(.black.opacity(0.55)))
                    context.fill(Path(ellipseIn: CGRect(x: corner.x - r, y: corner.y - r, width: r * 1.3, height: r * 1.3)), with: .color(.white.opacity(0.35)))
                }
            }
        }
    }

    private func drawFire(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        // Red glow rising from the bottom, flickering a little.
        let flicker = 0.85 + 0.15 * sin(time * 9) * sin(time * 3.7)
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: Color(red: 0.7, green: 0.08, blue: 0.02).opacity(0.55 * flicker), location: 0.8),
                    .init(color: Color(red: 1.0, green: 0.35, blue: 0.05).opacity(0.8 * flicker), location: 1)
                ]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
            )
        )
        // Flame tongues along the bottom edge.
        var flames = Path()
        let base = size.height
        flames.move(to: CGPoint(x: 0, y: base))
        var x: CGFloat = 0
        while x <= size.width + 12 {
            let height = 18 + 22 * abs(sin(Double(x) * 0.07 + time * 4)) + 10 * abs(sin(Double(x) * 0.19 - time * 6))
            flames.addQuadCurve(to: CGPoint(x: x + 6, y: base - height), control: CGPoint(x: x, y: base - height * 0.5))
            flames.addQuadCurve(to: CGPoint(x: x + 12, y: base), control: CGPoint(x: x + 12, y: base - height * 0.5))
            x += 12
        }
        flames.closeSubpath()
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.fill(flames, with: .linearGradient(
                Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.3), Color(red: 1, green: 0.3, blue: 0.02), Color(red: 0.6, green: 0.02, blue: 0)]),
                startPoint: CGPoint(x: 0, y: base), endPoint: CGPoint(x: 0, y: base - 50)
            ))
        }
    }
}
