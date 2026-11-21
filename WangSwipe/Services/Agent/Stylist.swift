import UIKit

/// One line of the Agent chat.
struct ChatMessage: Identifiable, Equatable, Sendable {
    enum Role: Sendable { case user, assistant }

    let id = UUID()
    var role: Role
    /// What the chat shows.
    var text: String
    /// What was sent to the model, when it differs (user turns carry what's on screen).
    var sentText: String? = nil
}

enum StylistError: LocalizedError, Equatable {
    case missingAPIKey
    case httpStatus(Int, String)
    case refused
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your Gemini API key in Setup to chat with the agent."
        case .httpStatus(let code, let body): "The agent service answered \(code): \(body)"
        case .refused: "The agent declined to answer that one. Try asking another way."
        case .badResponse: "The agent sent back something the app couldn't read."
        }
    }
}

/// What the agent knows about: the wardrobe, what's on screen, what the user kept,
/// and (on the first message) their photo and any finished try-on.
struct StylistContext {
    var wardrobe: [Product]
    var showing: [Product]
    var kept: [Product]
    var photo: UIImage?
    var look: UIImage?
}

/// Talks to Google's Gemini API (Gemini 4 Neon, medium thinking) with streaming.
///
/// Prototype only: the key lives in the device Keychain. Before shipping, move
/// this call behind your own server so the key never leaves it.
struct GeminiStylist: Sendable {
    static let model = "gemini-4-neon"
    static let thinkingLevel = "medium"
    static var endpoint: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse")!
    }

    let apiKey: String
    var session: URLSession = .shared

    /// Streams the reply's text as it arrives.
    func reply(to body: Data) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.isEmpty else { throw StylistError.missingAPIKey }
                    var request = URLRequest(url: Self.endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
                    request.httpBody = body

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw StylistError.badResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        var text = ""
                        for try await line in bytes.lines {
                            text += line
                            if text.count > 600 { break }
                        }
                        throw StylistError.httpStatus(http.statusCode, Self.errorMessage(in: text) ?? String(text.prefix(300)))
                    }
                    for try await line in bytes.lines {
                        switch Self.parse(line) {
                        case .text(let piece): continuation.yield(piece)
                        case .refused: throw StylistError.refused
                        case .failed(let message): throw StylistError.httpStatus(200, message)
                        case .done: continuation.finish(); return
                        case .other: continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Request

    static func requestBody(history: [ChatMessage], context: StylistContext, firstImages: [UIImage]) throws -> Data {
        var contents: [[String: Any]] = []
        for (index, message) in history.enumerated() {
            switch message.role {
            case .assistant:
                contents.append(["role": "model", "parts": [["text": message.text]]])
            case .user:
                var parts: [[String: Any]] = []
                if index == 0 {
                    // Photos go on the first message only, so later requests repeat the same start.
                    for image in firstImages {
                        if let data = image.normalizedUp().resized(maxDimension: 1024).jpegData(compressionQuality: 0.8) {
                            parts.append(["inlineData": ["mimeType": "image/jpeg", "data": data.base64EncodedString()]])
                        }
                    }
                }
                parts.append(["text": message.sentText ?? message.text])
                contents.append(["role": "user", "parts": parts])
            }
        }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": systemPrompt(wardrobe: context.wardrobe)]]],
            "contents": contents,
            "generationConfig": [
                "thinkingConfig": ["thinkingLevel": thinkingLevel],
                "maxOutputTokens": 8192
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func systemPrompt(wardrobe: [Product]) -> String {
        let lines = wardrobe.map { product in
            "- \(MensSection.of(product).title.lowercased()): \(product.brand ?? product.storeName) \(product.title), \(product.formattedPrice) at \(product.storeName)"
        }
        return """
        You are the stylist inside WangSwipe, a retro "wardrobe computer" iPhone app for men's clothing. \
        The user flips through a small wardrobe of real pieces from FWRD, Grailed and Farfetch, shuffles \
        outfits (a top panel and a bottom panel), and presses Dress Me to see an outfit on their own photo.

        Give specific, friendly advice in plain text with no Markdown, usually 2 to 5 sentences. \
        Recommend pieces from the wardrobe below by brand and name when they fit the question. \
        If the user asks for their perfect match, pick the one top and one bottom from the wardrobe \
        that suit them best (use their photo if attached) and say why in a sentence or two. \
        You can suggest things the wardrobe doesn't have (shoes, accessories, layers), but say they aren't in it. \
        If a photo is attached, it's the user, and a second image is their latest try-on: use them for color, \
        proportion and fit advice. Be kind about their body and don't rate their face or looks.

        The wardrobe:
        \(lines.joined(separator: "\n"))
        """
    }

    /// Text added to each user message so the agent knows what's on screen right now.
    static func screenNote(_ context: StylistContext) -> String {
        let showing = context.showing.map { "\($0.brand ?? $0.storeName) \($0.title)" }
        let kept = context.kept.map { "\($0.brand ?? $0.storeName) \($0.title)" }
        var note = "On screen now: " + (showing.isEmpty ? "nothing" : showing.joined(separator: " + ")) + "."
        if !kept.isEmpty { note += " Kept pieces: " + kept.joined(separator: ", ") + "." }
        return note
    }

    // MARK: Streaming events

    enum Event: Equatable {
        case text(String)
        case refused
        case failed(String)
        case done
        case other
    }

    /// Reads one server-sent-events line: each `data:` line is a partial response.
    static func parse(_ line: String) -> Event {
        guard line.hasPrefix("data:") else { return .other }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .other }
        if let error = json["error"] as? [String: Any] {
            return .failed(error["message"] as? String ?? "Unknown error")
        }
        if let feedback = json["promptFeedback"] as? [String: Any], feedback["blockReason"] != nil {
            return .refused
        }
        guard let candidate = (json["candidates"] as? [[String: Any]])?.first else { return .other }
        let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        // Skip thinking summaries; only the answer is shown.
        let text = parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
        if !text.isEmpty { return .text(text) }
        switch candidate["finishReason"] as? String {
        case "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION": return .refused
        case .some: return .done
        case .none: return .other
        }
    }

    /// Pulls `error.message` out of an error body, if it's JSON.
    static func errorMessage(in body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any]
        else { return nil }
        return error["message"] as? String
    }
}
