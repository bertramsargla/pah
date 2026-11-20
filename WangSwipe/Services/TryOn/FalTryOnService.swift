import UIKit

/// Hosted try-on models on fal.ai. Prices are per generated image, as listed
/// on fal.ai in November 2026; check before relying on them.
enum FalTryOnModel: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Google's Virtual Try-On model. Inputs: person_image_url, product_image_url. ~$0.075/image,
    /// about 35 s per garment in our test.
    case googleVTO = "google/virtual-try-on"
    /// FASHN v1.6 in performance mode. Inputs: model_image, garment_image, category, mode.
    /// $0.075/image; FASHN quotes ~7 s in performance mode.
    case fashn = "fal-ai/fashn/tryon/v1.6"
    /// Google's Nano Banana image editor. Takes the photo and every garment in one call
    /// (image_urls + prompt). $0.0398/image. A general editor, not a dedicated try-on model.
    case nanoBanana = "fal-ai/nano-banana/edit"
    /// Kling Kolors v1.5. Inputs: human_image_url, garment_image_url. ~$0.07/image.
    case klingKolors = "fal-ai/kling/v1-5/kolors-virtual-try-on"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .googleVTO: "Google Virtual Try-On (slow, ~$0.075/piece)"
        case .fashn: "FASHN v1.6 fast (~$0.075/piece)"
        case .nanoBanana: "Nano Banana, whole outfit (~$0.04/outfit)"
        case .klingKolors: "Kling Kolors v1.5 (~$0.07/piece)"
        }
    }

    /// Whether one call dresses the whole outfit instead of one call per piece.
    var dressesWholeOutfit: Bool { self == .nanoBanana }
}

/// Calls a fal.ai try-on model directly from the phone.
///
/// Prototype only: the key lives in the device Keychain. Before shipping,
/// move this call behind your own server so the key never leaves it, and add
/// consent and retention rules for users' body photos.
struct FalTryOnService: TryOnService {
    let apiKey: String
    let model: FalTryOnModel
    var session: URLSession = .shared

    var label: String { "AI try-on" }

    var dressesWholeOutfit: Bool { model.dressesWholeOutfit }

    func render(person: UIImage, garment: UIImage, product: Product) async throws -> UIImage {
        try await renderOutfit(person: person, garments: [garment], products: [product])
    }

    func renderOutfit(person: UIImage, garments: [UIImage], products: [Product]) async throws -> UIImage {
        guard !apiKey.isEmpty else { throw TryOnError.missingAPIKey }
        guard let personURI = person.normalizedUp().resized(maxDimension: 1024).jpegDataURI() else {
            throw TryOnError.encodingFailed
        }
        let garmentURIs = garments.compactMap {
            $0.normalizedUp().resized(maxDimension: 1024).flattened(on: .white).jpegDataURI()
        }
        guard garmentURIs.count == garments.count, !garmentURIs.isEmpty else { throw TryOnError.encodingFailed }

        if model.dressesWholeOutfit {
            return try await call(Self.outfitRequestBody(personImage: personURI, garmentImages: garmentURIs, products: products))
        }
        // One call per garment, each on top of the last result.
        var current = personURI
        var result = person
        for (garmentURI, product) in zip(garmentURIs, products) {
            result = try await call(Self.requestBody(model: model, personImage: current, garmentImage: garmentURI, category: product.category))
            guard let next = result.resized(maxDimension: 1024).jpegDataURI() else { throw TryOnError.encodingFailed }
            current = next
        }
        return result
    }

    private func call(_ body: [String: Any]) async throws -> UIImage {
        var request = URLRequest(url: URL(string: "https://fal.run/\(model.rawValue)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TryOnError.unexpectedResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(decoding: data.prefix(300), as: UTF8.self)
            throw TryOnError.httpStatus(http.statusCode, body)
        }

        let resultURL = try Self.resultImageURL(from: data)
        let (imageData, _) = try await session.data(from: resultURL)
        guard let image = UIImage(data: imageData) else { throw TryOnError.badImage }
        return image
    }

    /// fal accepts either public URLs or base64 data URIs for image inputs.
    static func requestBody(model: FalTryOnModel, personImage: String, garmentImage: String,
                            category: GarmentCategory = .top) -> [String: Any] {
        switch model {
        case .googleVTO:
            return ["person_image_url": personImage, "product_image_url": garmentImage, "num_images": 1]
        case .fashn:
            let fashnCategory = switch category {
            case .top, .outerwear: "tops"
            case .bottom: "bottoms"
            case .dress: "one-pieces"
            }
            return ["model_image": personImage, "garment_image": garmentImage, "category": fashnCategory,
                    "mode": "performance", "output_format": "jpeg"]
        case .nanoBanana:
            return outfitRequestBody(personImage: personImage, garmentImages: [garmentImage], products: [])
        case .klingKolors:
            return ["human_image_url": personImage, "garment_image_url": garmentImage]
        }
    }

    /// Nano Banana: the photo first, then each garment, with a prompt naming them.
    static func outfitRequestBody(personImage: String, garmentImages: [String], products: [Product]) -> [String: Any] {
        var pieces: [String] = []
        for index in garmentImages.indices {
            let name = index < products.count ? products[index].title : "garment"
            let slot = index < products.count ? (products[index].category == .bottom ? "bottom" : "top") : "piece"
            pieces.append("image \(index + 2) is the \(slot): \(name)")
        }
        let prompt = """
        Virtual try-on. Image 1 is a photo of a person; \(pieces.joined(separator: "; ")). \
        Dress the person from image 1 in these garments, matching each garment's color, pattern, fabric and fit exactly. \
        Keep the person's face, hair, skin tone, body shape, pose, framing and background exactly as in image 1. \
        Only change the clothing the new garments cover. Photorealistic.
        """
        return ["prompt": prompt, "image_urls": [personImage] + garmentImages, "num_images": 1, "output_format": "jpeg"]
    }

    /// Reads `images[0].url` (Google VTO, FASHN, Nano Banana) or `image.url` (Kling).
    static func resultImageURL(from data: Data) throws -> URL {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TryOnError.unexpectedResponse
        }
        let first = (json["images"] as? [[String: Any]])?.first ?? (json["image"] as? [String: Any])
        guard let urlString = first?["url"] as? String, let url = URL(string: urlString) else {
            throw TryOnError.unexpectedResponse
        }
        return url
    }
}
