import UIKit

/// Fallback for when Vision can't run (it doesn't in the iOS Simulator):
/// finds the person in a photo with a plain background by flood-filling the
/// background in from the edges, then estimates shoulders and hips from
/// typical body proportions. Rough, but enough for the free preview.
enum PlainBackgroundSegmenter {
    static func segment(_ image: UIImage) -> (mask: CGImage, body: BodyLandmarks)? {
        guard let source = image.cgImage else { return nil }
        let fullSize = image.size
        let factor = min(1, 400 / max(fullSize.width, fullSize.height))
        let w = max(Int(fullSize.width * factor), 1)
        let h = max(Int(fullSize.height * factor), 1)

        // 1. Read pixels at a small working size.
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drew: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drew else { return nil }

        func color(_ i: Int) -> (Int, Int, Int) {
            (Int(pixels[i * 4]), Int(pixels[i * 4 + 1]), Int(pixels[i * 4 + 2]))
        }
        func distance(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Int {
            abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2)
        }

        // 2. Average border color = the background.
        var border: [Int] = []
        for x in 0..<w { border.append(x); border.append((h - 1) * w + x) }
        for y in 0..<h { border.append(y * w); border.append(y * w + w - 1) }
        let sum = border.reduce((0, 0, 0)) { acc, i in
            let c = color(i); return (acc.0 + c.0, acc.1 + c.1, acc.2 + c.2)
        }
        let background = (sum.0 / border.count, sum.1 / border.count, sum.2 / border.count)

        // 3. Flood fill: step to neighbours that look like their neighbour and like the background.
        var isBackground = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        for i in border where distance(color(i), background) < 90 && !isBackground[i] {
            isBackground[i] = true
            stack.append(i)
        }
        while let i = stack.popLast() {
            let x = i % w, y = i / w
            let here = color(i)
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            where nx >= 0 && ny >= 0 && nx < w && ny < h {
                let n = ny * w + nx
                guard !isBackground[n] else { continue }
                let c = color(n)
                if distance(c, here) < 24 && distance(c, background) < 90 {
                    isBackground[n] = true
                    stack.append(n)
                }
            }
        }

        // 4. Person rows and proportions.
        func extent(row: Int) -> (Int, Int)? {
            var minX = Int.max, maxX = Int.min
            for x in 0..<w where !isBackground[row * w + x] {
                minX = min(minX, x); maxX = max(maxX, x)
            }
            return minX <= maxX ? (minX, maxX) : nil
        }
        let personRows = (0..<h).filter { row in
            guard let e = extent(row: row) else { return false }
            return e.1 - e.0 >= 3
        }
        guard let top = personRows.first, let bottom = personRows.last, bottom - top > h / 3 else { return nil }
        let height = CGFloat(bottom - top)
        let shoulderRow = top + Int(height * 0.19)
        let hipRow = top + Int(height * 0.52)
        guard let shoulders = extent(row: shoulderRow) else { return nil }
        let inset = CGFloat(shoulders.1 - shoulders.0) * 0.12
        let up = 1 / factor
        let left = (CGFloat(shoulders.0) + inset) * up
        let right = (CGFloat(shoulders.1) - inset) * up
        let body = BodyLandmarks(
            shoulderLeft: CGPoint(x: left, y: CGFloat(shoulderRow) * up),
            shoulderRight: CGPoint(x: right, y: CGFloat(shoulderRow) * up),
            hipLeft: CGPoint(x: left, y: CGFloat(hipRow) * up),
            hipRight: CGPoint(x: right, y: CGFloat(hipRow) * up),
            ankleY: (CGFloat(top) + height * 0.95) * up
        )

        // 5. Mask image (white = person), scaled back to full size.
        var gray = isBackground.map { $0 ? UInt8(0) : UInt8(255) }
        let small: CGImage? = gray.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            )?.makeImage()
        }
        guard let small,
              let full = CGContext(
                data: nil, width: Int(fullSize.width), height: Int(fullSize.height), bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
              )
        else { return nil }
        full.interpolationQuality = .high
        full.draw(small, in: CGRect(origin: .zero, size: CGSize(width: Int(fullSize.width), height: Int(fullSize.height))))
        guard let mask = full.makeImage() else { return nil }
        return (mask, body)
    }
}
