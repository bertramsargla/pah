import UIKit
import Vision

/// Free, offline stand-in for a real try-on model. It finds the person's
/// shoulders and hips with Vision and lays the garment image over that region.
/// It looks like a sticker, not a fitted garment, but it exercises the whole
/// flow (photo in, image out, caching, card states) without spending money.
struct MockTryOnService: TryOnService {
    var label: String { "Preview" }
    var latency: Duration = .milliseconds(600)

    func render(person: UIImage, garment: UIImage, product: Product) async throws -> UIImage {
        try await Task.sleep(for: latency)
        let base = person.normalizedUp().resized(maxDimension: 1280)
        let body = BodyLandmarks.detect(in: base)
        let region = Self.region(for: product.category, body: body, in: base.size)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: base.size, format: format).image { _ in
            base.draw(in: CGRect(origin: .zero, size: base.size))
            // Stretch to the body region so the garment covers what the person is wearing.
            garment.draw(in: region, blendMode: .normal, alpha: 1)
        }
    }

    /// Where the garment goes, in image points.
    static func region(for category: GarmentCategory, body: BodyLandmarks?, in size: CGSize) -> CGRect {
        if let body {
            let shoulderWidth = max(body.shoulderRight.x - body.shoulderLeft.x, size.width * 0.15)
            let shoulderY = min(body.shoulderLeft.y, body.shoulderRight.y)
            let hipY = max(body.hipLeft.y, body.hipRight.y)
            let torso = max(hipY - shoulderY, size.height * 0.15)
            let centerX = (body.shoulderLeft.x + body.shoulderRight.x) / 2
            let ankleY = body.ankleY ?? min(hipY + torso * 2.2, size.height)

            switch category {
            case .top:
                let width = shoulderWidth * 2.3
                return CGRect(x: centerX - width / 2, y: shoulderY - torso * 0.2, width: width, height: torso * 1.4)
            case .outerwear:
                let width = shoulderWidth * 2.5
                return CGRect(x: centerX - width / 2, y: shoulderY - torso * 0.22, width: width, height: torso * 1.6)
            case .dress:
                let width = shoulderWidth * 2.1
                return CGRect(x: centerX - width / 2, y: shoulderY - torso * 0.15, width: width, height: (ankleY - shoulderY) * 0.9)
            case .bottom:
                let width = shoulderWidth * 1.5
                return CGRect(x: centerX - width / 2, y: hipY - torso * 0.12, width: width, height: ankleY - hipY + torso * 0.1)
            }
        }

        // No body found: use fixed fractions of the frame.
        let fractions: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) = switch category {
        case .top: (0.2, 0.2, 0.6, 0.35)
        case .outerwear: (0.15, 0.18, 0.7, 0.42)
        case .dress: (0.2, 0.2, 0.6, 0.6)
        case .bottom: (0.25, 0.5, 0.5, 0.45)
        }
        return CGRect(
            x: size.width * fractions.x,
            y: size.height * fractions.y,
            width: size.width * fractions.w,
            height: size.height * fractions.h
        )
    }
}

/// Key body points in image coordinates (origin top-left, in points).
struct BodyLandmarks {
    var shoulderLeft: CGPoint
    var shoulderRight: CGPoint
    var hipLeft: CGPoint
    var hipRight: CGPoint
    var ankleY: CGFloat?

    static func detect(in image: UIImage) -> BodyLandmarks? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let points = try? observation.recognizedPoints(.all)
        else { return nil }

        let size = image.size
        func point(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = points[name], p.confidence > 0.3 else { return nil }
            // Vision uses a normalized, bottom-left origin.
            return CGPoint(x: p.location.x * size.width, y: (1 - p.location.y) * size.height)
        }

        guard
            let a = point(.leftShoulder), let b = point(.rightShoulder),
            let c = point(.leftHip), let d = point(.rightHip)
        else { return nil }

        let ankles = [point(.leftAnkle), point(.rightAnkle)].compactMap { $0?.y }
        return BodyLandmarks(
            shoulderLeft: a.x < b.x ? a : b,
            shoulderRight: a.x < b.x ? b : a,
            hipLeft: c.x < d.x ? c : d,
            hipRight: c.x < d.x ? d : c,
            ankleY: ankles.max()
        )
    }
}
