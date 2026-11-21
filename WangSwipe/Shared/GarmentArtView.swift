import SwiftUI

/// Simple drawn garment, used when a product has no photo (the mock stores).
struct GarmentArtView: View {
    let category: GarmentCategory
    let color: Color
    var showsBackground = true

    init(category: GarmentCategory, hex: String?, showsBackground: Bool = true) {
        self.category = category
        self.color = Color(hex: hex ?? "#888888")
        self.showsBackground = showsBackground
    }

    var body: some View {
        ZStack {
            if showsBackground {
                LinearGradient(
                    colors: [Retro.panel, Retro.panelAlt],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            GarmentShape(category: category)
                .fill(color)
                // Soft light-to-shadow shading so it reads as fabric, not a flat cutout.
                .overlay(
                    GarmentShape(category: category).fill(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .clear, .black.opacity(0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(
                    GarmentDetails(category: category)
                        .stroke(.black.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
                )
                .overlay(GarmentShape(category: category).stroke(.black.opacity(0.45), lineWidth: 2.5))
                .aspectRatio(0.75, contentMode: .fit)
                .padding(showsBackground ? 36 : 0)
        }
    }

    /// Renders the art to an image, for sending to a try-on service.
    @MainActor
    static func renderImage(for product: Product, size: CGSize = CGSize(width: 600, height: 800)) -> UIImage? {
        let view = GarmentArtView(category: product.category, hex: product.swatchHex, showsBackground: false)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage
    }
}

/// Outline of a garment in a unit square, scaled to the given rect.
struct GarmentShape: Shape {
    let category: GarmentCategory

    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = switch category {
        case .top:
            [(0.38, 0.08), (0.62, 0.08), (0.95, 0.22), (0.86, 0.40), (0.76, 0.34),
             (0.76, 0.95), (0.24, 0.95), (0.24, 0.34), (0.14, 0.40), (0.05, 0.22)]
        case .outerwear:
            [(0.38, 0.06), (0.62, 0.06), (0.92, 0.18), (0.99, 0.78), (0.86, 0.80), (0.78, 0.36),
             (0.78, 0.96), (0.22, 0.96), (0.22, 0.36), (0.14, 0.80), (0.01, 0.78), (0.08, 0.18)]
        case .dress:
            [(0.40, 0.04), (0.60, 0.04), (0.68, 0.08), (0.66, 0.40), (0.88, 0.97),
             (0.12, 0.97), (0.34, 0.40), (0.32, 0.08)]
        case .bottom:
            [(0.24, 0.04), (0.76, 0.04), (0.82, 0.97), (0.56, 0.97), (0.50, 0.36),
             (0.44, 0.97), (0.18, 0.97)]
        }

        var path = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: rect.minX + point.0 * rect.width, y: rect.minY + point.1 * rect.height)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

/// Seams, necklines and stitching drawn on top of a `GarmentShape`.
struct GarmentDetails: Shape {
    let category: GarmentCategory

    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        switch category {
        case .top:
            path.move(to: p(0.38, 0.08))
            path.addQuadCurve(to: p(0.62, 0.08), control: p(0.5, 0.2))
            path.move(to: p(0.25, 0.90)); path.addLine(to: p(0.75, 0.90))
            path.move(to: p(0.10, 0.33)); path.addLine(to: p(0.17, 0.37))
            path.move(to: p(0.90, 0.33)); path.addLine(to: p(0.83, 0.37))
        case .outerwear:
            path.move(to: p(0.38, 0.06)); path.addLine(to: p(0.5, 0.30)); path.addLine(to: p(0.62, 0.06))
            path.move(to: p(0.5, 0.30)); path.addLine(to: p(0.5, 0.95))
            path.move(to: p(0.28, 0.62)); path.addLine(to: p(0.42, 0.62))
            path.move(to: p(0.58, 0.62)); path.addLine(to: p(0.72, 0.62))
        case .dress:
            path.move(to: p(0.40, 0.04))
            path.addQuadCurve(to: p(0.60, 0.04), control: p(0.5, 0.14))
            path.move(to: p(0.34, 0.40)); path.addLine(to: p(0.66, 0.40))
            path.move(to: p(0.15, 0.93)); path.addLine(to: p(0.85, 0.93))
        case .bottom:
            path.move(to: p(0.245, 0.11)); path.addLine(to: p(0.755, 0.11))
            path.move(to: p(0.5, 0.11)); path.addLine(to: p(0.5, 0.30))
            path.move(to: p(0.30, 0.16)); path.addQuadCurve(to: p(0.42, 0.24), control: p(0.33, 0.24))
            path.move(to: p(0.70, 0.16)); path.addQuadCurve(to: p(0.58, 0.24), control: p(0.67, 0.24))
        }
        return path
    }
}

extension Color {
    /// Accepts "#RRGGBB" or "RRGGBB". Falls back to gray.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(cleaned, radix: 16) ?? 0x888888
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
