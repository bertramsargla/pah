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

    /// Sends a question. With Senso, the knowledge base is searched first and the
    /// passages it finds go to Gemini with the question.
    func send(_ text: String, apiKey: String, senso: SensoClient? = nil, context: StylistContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isReplying else { return }
        errorText = nil
        failedQuestion = nil
        if messages.isEmpty {
            firstImages = [context.photo, context.look].compactMap { $0 }
        }
        let screenNote = GeminiStylist.screenNote(context)
        messages.append(ChatMessage(role: .user, text: trimmed, sentText: screenNote + "\n\n" + trimmed))
        let questionIndex = messages.count - 1

        isReplying = true
        messages.append(ChatMessage(role: .assistant, text: ""))
        let replyIndex = messages.count - 1
        let stylist = GeminiStylist(apiKey: apiKey)
        let images = firstImages

        task = Task { [weak self] in
            if let senso {
                do {
                    let passages = try await senso.passages(for: trimmed)
                    self?.attach(passages, screenNote: screenNote, question: questionIndex, reply: replyIndex)
                } catch {
                    self?.setCaption("Senso search skipped: \(error.localizedDescription)", at: replyIndex)
                }
            }
            guard let self, !Task.isCancelled else { return }
            do {
                let body = try GeminiStylist.requestBody(history: Array(self.messages.prefix(replyIndex)),
                                                         context: context, firstImages: images)
                for try await piece in stylist.reply(to: body) {
                    self.append(piece, at: replyIndex)
                }
            } catch {
                self.errorText = error.localizedDescription
            }
            self.finishReply(at: replyIndex)
        }
    }

    private func attach(_ passages: [SensoClient.Passage], screenNote: String, question: Int, reply: Int) {
        guard !passages.isEmpty, question < messages.count, reply < messages.count else { return }
        let message = messages[question]
        messages[question].sentText = screenNote + "\n\n" + SensoClient.note(passages) + "\n\n" + message.text
        var titles: [String] = []
        for passage in passages where !titles.contains(passage.title) { titles.append(passage.title) }
        messages[reply].caption = "From Senso: " + titles.joined(separator: ", ")
    }

    private func setCaption(_ caption: String, at index: Int) {
        guard index < messages.count else { return }
        messages[index].caption = caption
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

    #if DEBUG
    /// A canned exchange for screenshots (`-agentDemo YES`); nothing is sent.
    func showDemo(question: String, reply: String) {
        messages = [ChatMessage(role: .user, text: question), ChatMessage(role: .assistant, text: reply)]
    }
    #endif

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
