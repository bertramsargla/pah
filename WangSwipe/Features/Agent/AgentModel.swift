import SwiftUI
import Observation

/// The Agent tab's conversation with the stylist.
@MainActor
@Observable
final class AgentModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var isReplying = false
    private(set) var errorText: String?
    /// The question that failed, handed back to the input box for a retry.
    private(set) var failedQuestion: String?

    /// Photo and try-on attached to the first message, kept so every later
    /// request sends the same first message (and stays cacheable).
    @ObservationIgnored private var firstImages: [UIImage] = []
    @ObservationIgnored private var task: Task<Void, Never>?

    func send(_ text: String, apiKey: String, context: StylistContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isReplying else { return }
        errorText = nil
        failedQuestion = nil
        if messages.isEmpty {
            firstImages = [context.photo, context.look].compactMap { $0 }
        }
        messages.append(ChatMessage(role: .user, text: trimmed,
                                    sentText: ClaudeStylist.screenNote(context) + "\n\n" + trimmed))
        let body: Data
        do {
            body = try ClaudeStylist.requestBody(history: messages, context: context, firstImages: firstImages)
        } catch {
            errorText = error.localizedDescription
            return
        }

        isReplying = true
        messages.append(ChatMessage(role: .assistant, text: ""))
        let replyIndex = messages.count - 1
        let stylist = ClaudeStylist(apiKey: apiKey)

        task = Task { [weak self] in
            do {
                for try await piece in stylist.reply(to: body) {
                    self?.append(piece, at: replyIndex)
                }
            } catch {
                self?.errorText = error.localizedDescription
            }
            self?.finishReply(at: replyIndex)
        }
    }

    private func append(_ piece: String, at index: Int) {
        guard index < messages.count, messages[index].role == .assistant else { return }
        messages[index].text += piece
    }

    private func finishReply(at index: Int) {
        isReplying = false
        // Drop an empty reply and hand its question back, so a retry starts clean.
        if index < messages.count, messages[index].text.isEmpty {
            messages.remove(at: index)
            if let last = messages.last, last.role == .user {
                failedQuestion = last.text
                messages.removeLast()
            }
        }
    }

    func reset() {
        task?.cancel()
        task = nil
        messages = []
        firstImages = []
        errorText = nil
        failedQuestion = nil
        isReplying = false
    }
}
