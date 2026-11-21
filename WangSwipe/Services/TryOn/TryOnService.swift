import UIKit

/// Puts a garment onto the user's photo. Swap implementations in
/// `AppModel.makeTryOnService()`: the mock runs on device for free, the fal
/// service calls a paid hosted model.
protocol TryOnService: Sendable {
    /// Short label shown in the mirror, such as "Preview" or "AI try-on".
    var label: String { get }
    func render(person: UIImage, garment: UIImage, product: Product) async throws -> UIImage

    /// True when `renderOutfit` dresses everything in one call (faster and cheaper than one per piece).
    var dressesWholeOutfit: Bool { get }
    /// Puts every garment on at once. Garments and products are in the same order.
    func renderOutfit(person: UIImage, garments: [UIImage], products: [Product]) async throws -> UIImage
}

extension TryOnService {
    var dressesWholeOutfit: Bool { false }

    func renderOutfit(person: UIImage, garments: [UIImage], products: [Product]) async throws -> UIImage {
        var current = person
        for (garment, product) in zip(garments, products) {
            current = try await render(person: current, garment: garment, product: product)
        }
        return current
    }
}

enum TryOnError: LocalizedError, Equatable {
    case missingAPIKey
    case encodingFailed
    case httpStatus(Int, String)
    case unexpectedResponse
    case badImage

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your fal.ai key in Setup to use AI try-on."
        case .encodingFailed: "Couldn't prepare the photos for upload."
        case .httpStatus(let code, let body): "Try-on service error \(code): \(body)"
        case .unexpectedResponse: "The try-on service sent back something unexpected."
        case .badImage: "Couldn't read the try-on image."
        }
    }
}
