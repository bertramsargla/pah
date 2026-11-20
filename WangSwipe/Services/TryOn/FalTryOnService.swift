import UIKit

/// Hosted try-on models on fal.ai. Prices are per generated image, as listed
/// on fal.ai in November 2026; check before relying on them.
enum FalTryOnModel: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Google's Virtual Try-On model. Inputs: person_image_url, product_image_url. ~$0.075/image.
    case googleVTO = "google/virtual-try-on"
    /// Kling Kolors v1.5. Inputs: human_image_url, garment_image_url. ~$0.07/image.
    case klingKolors = "fal-ai/kling/v1-5/kolors-virtual-try-on"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .googleVTO: "Google Virtual Try-On (~$0.075)"
        case .klingKolors: "Kling Kolors v1.5 (~$0.07)"
        }
    }
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

    func render(person: UIImage, garment: UIImage, product: Product) async throws -> UIImage {
        guard !apiKey.isEmpty else { throw TryOnError.missingAPIKey }
        guard
            let personURI = person.normalizedUp().resized(maxDimension: 1024).jpegDataURI(),
            let garmentURI = garment.normalizedUp().resized(maxDimension: 1024).jpegDataURI()
        else { throw TryOnError.encodingFailed }

        var request = URLRequest(url: URL(string: "https://fal.run/\(model.rawValue)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: Self.requestBody(model: model, personImage: personURI, garmentImage: garmentURI)
        )

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
    static func requestBody(model: FalTryOnModel, personImage: String, garmentImage: String) -> [String: Any] {
        switch model {
        case .googleVTO:
            return ["person_image_url": personImage, "product_image_url": garmentImage, "num_images": 1]
        case .klingKolors:
            return ["human_image_url": personImage, "garment_image_url": garmentImage]
        }
    }

    /// Reads `images[0].url` (Google VTO) or `image.url` (Kling).
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
