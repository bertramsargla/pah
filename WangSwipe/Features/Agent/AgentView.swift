import SwiftUI

/// Chat with an AI stylist about the wardrobe and the outfit on screen.
struct AgentView: View {
    @Environment(AppModel.self) private var appModel
    @State private var draft = ""
    @FocusState private var typing: Bool

    private var agent: AgentModel { appModel.agent }

    private let suggestions = ["Find me the perfect match"]

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(title: "Agent")
                .overlay(alignment: .leading) {
                    if !agent.messages.isEmpty {
                        Button("New chat") { agent.reset() }
                            .font(Retro.font(11, weight: .bold))
                            .textCase(.uppercase)
                            .foregroundStyle(Retro.onBar)
                            .padding(.leading, 12)
                    }
                }

            ZStack {
                SkinBackdrop()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if agent.messages.isEmpty { intro }
                            ForEach(agent.messages) { message in
                                bubble(message).id(message.id)
                            }
                            if let error = agent.errorText {
                                Text(error)
                                    .font(Retro.font(11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.red.opacity(0.85))
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(14)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: agent.messages.last?.text) {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }

            inputBar
        }
        .overlay(Scanlines())
        .onChange(of: agent.failedQuestion) { _, question in
            if let question, draft.isEmpty { draft = question }
        }
    }

    // MARK: Pieces

    private var intro: some View {
        VStack(spacing: 10) {
            RetroPanel {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your stylist").font(Retro.font(16))
                    Text("Ask about the outfit on screen, what to pair with a piece, or what to add. The agent sees the wardrobe, what you kept, and your photo.")
                        .font(Retro.font(12, weight: .medium))
                    if !appModel.hasGeminiKey {
                        Text("Add your Gemini API key in Setup first.")
                            .font(Retro.font(12, weight: .bold))
                    }
                }
                .textCase(.uppercase)
                .foregroundStyle(Retro.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(suggestions, id: \.self) { suggestion in
                Button(suggestion) { send(suggestion) }
                    .buttonStyle(BevelButtonStyle(size: 13))
            }
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }
            Group {
                if message.text.isEmpty {
                    ProgressView().tint(Retro.ink)
                } else {
                    Text(message.text)
                        .font(Retro.font(13, weight: .medium))
                        .textSelection(.enabled)
                }
            }
            .foregroundStyle(isUser ? Retro.onBar : Retro.ink)
            .padding(10)
            .background(isUser ? Retro.bar : Retro.panel)
            .overlay(Bevel(raised: !isUser, width: 3))
            .overlay(Rectangle().stroke(Retro.ink, lineWidth: 1.5))
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask your stylist", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(Retro.font(14, weight: .medium))
                .foregroundStyle(Retro.ink)
                .padding(8)
                .background(Retro.panel)
                .overlay(Bevel(raised: false, width: 3))
                .focused($typing)
                .submitLabel(.send)
                .onSubmit { send(draft) }
            Button("Send") { send(draft) }
                .buttonStyle(.bevelPrimary)
                .frame(width: 96, height: 44)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || agent.isReplying)
        }
        .padding(8)
        .background(Retro.bar)
    }

    private func send(_ text: String) {
        agent.send(text, apiKey: appModel.geminiAPIKey, context: appModel.stylistContext())
        draft = ""
    }
}
