import CryptoKit
import Foundation

/// Senso (senso.ai) is the stylist's knowledge base. The app files two documents
/// into it, a men's style guide and the current wardrobe, and before each Agent
/// reply it searches them for the passages that fit the question. Those passages
/// go to Gemini with the question, so answers rest on the same notes every time.
///
/// API: https://docs.senso.ai (base `https://apiv2.senso.ai/api/v1`, `X-API-Key` header).
/// Prototype only: the key lives in the device Keychain. Before shipping, move
/// these calls behind your own server so the key never leaves it.
struct SensoClient: Sendable {
    static let baseURL = URL(string: "https://apiv2.senso.ai/api/v1")!

    let apiKey: String
    var session: URLSession = .shared

    /// One passage the search found.
    struct Passage: Equatable, Sendable {
        var title: String
        var text: String
    }

    /// What filing a document returned.
    enum Filed: Equatable, Sendable {
        /// Accepted; Senso processes it in the background. Carries its knowledge-base node id.
        case accepted(nodeID: String?)
        /// Senso already has this exact text.
        case duplicate
    }

    // MARK: Calls

    /// Files raw text (POST /org/kb/raw). Searchable once Senso finishes processing it.
    func file(title: String, text: String) async throws -> Filed {
        let body = try JSONSerialization.data(withJSONObject: ["title": title, "text": text])
        let (data, status) = try await send(Self.request("org/kb/raw", method: "POST", body: body, apiKey: apiKey))
        if status == 409 { return .duplicate }
        try Self.check(status, data)
        return .accepted(nodeID: Self.nodeID(in: data))
    }

    /// The passages that best match a question (POST /org/search/context: chunks only, no answer).
    func passages(for query: String, limit: Int = 4) async throws -> [Passage] {
        let body = try JSONSerialization.data(withJSONObject: ["query": query, "max_results": limit])
        let (data, status) = try await send(Self.request("org/search/context", method: "POST", body: body, apiKey: apiKey))
        try Self.check(status, data)
        return Self.parsePassages(data)
    }

    /// Removes an earlier copy of a document (DELETE /org/kb/nodes/{id}).
    func remove(nodeID: String) async throws {
        let (data, status) = try await send(Self.request("org/kb/nodes/\(nodeID)", method: "DELETE", body: nil, apiKey: apiKey))
        guard status != 404 else { return }
        try Self.check(status, data)
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    // MARK: Building and reading (static so tests can check them)

    static func request(_ path: String, method: String, body: Data?, apiKey: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    static func check(_ status: Int, _ data: Data) throws {
        guard !(200..<300).contains(status) else { return }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = (json?["detail"] as? String) ?? (json?["message"] as? String)
            ?? ((json?["error"] as? [String: Any])?["message"] as? String)
            ?? (json?["error"] as? String)
            ?? String(decoding: data.prefix(200), as: UTF8.self)
        switch status {
        case 401: throw SensoError.badKey
        case 402: throw SensoError.outOfCredits
        default: throw SensoError.http(status, message)
        }
    }

    static func nodeID(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["kb_node_id"] as? String) ?? (json["id"] as? String)
    }

    /// Reads search results, tolerating the few shapes the docs show
    /// (`results` or `chunks`, each with `chunk_text`, `text` or `content`).
    static func parsePassages(_ data: Data) -> [Passage] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let list: [[String: Any]]
        if let array = json as? [[String: Any]] {
            list = array
        } else if let object = json as? [String: Any] {
            list = (object["results"] as? [[String: Any]]) ?? (object["chunks"] as? [[String: Any]])
                ?? (object["context"] as? [[String: Any]]) ?? []
        } else {
            list = []
        }
        return list.compactMap { item in
            let text = (item["chunk_text"] as? String) ?? (item["text"] as? String) ?? (item["content"] as? String) ?? ""
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Passage(title: (item["title"] as? String) ?? "Senso", text: trimmed)
        }
    }

    // MARK: The documents

    static let styleGuideTitle = "WangSwipe men's style guide"
    static let wardrobeTitle = "WangSwipe wardrobe"

    /// The wardrobe as one plain-text document, one piece per line, with the ids the
    /// agent uses for its Dress Me pick.
    static func wardrobeDocument(_ products: [Product]) -> String {
        let lines = products.map { product in
            var line = "- \(product.brand ?? product.storeName) \(product.title) (id \(product.id)): "
            line += "\(MensSection.of(product).title.lowercased()), \(product.formattedPrice) at \(product.storeName)"
            if let url = product.productURL { line += ", \(url.absoluteString)" }
            return line
        }
        return """
        The pieces in the WangSwipe wardrobe right now. Tops (shirts, sweaters, jackets) go in the upper panel, \
        pants and jeans in the lower panel; an outfit is one of each.

        \(lines.joined(separator: "\n"))
        """
    }

    /// Short fingerprint of a document, to skip filing the same text twice.
    static func fingerprint(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// The passages as a note added to the user's message for Gemini.
    static func note(_ passages: [Passage]) -> String {
        guard !passages.isEmpty else { return "" }
        let lines = passages.map { "- (\($0.title)) \($0.text.replacingOccurrences(of: "\n", with: " "))" }
        return "Notes from the style knowledge base (Senso), use them where they fit:\n" + lines.joined(separator: "\n")
    }
}

enum SensoError: LocalizedError, Equatable {
    case badKey
    case outOfCredits
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .badKey: "Senso didn't accept the key. Check it in Setup."
        case .outOfCredits: "The Senso account is out of credits."
        case .http(let code, let message): "Senso answered \(code): \(message)"
        }
    }
}
