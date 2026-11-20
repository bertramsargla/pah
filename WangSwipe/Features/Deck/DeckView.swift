import SwiftUI

struct DeckView: View {
    @Environment(AppModel.self) private var appModel

    private var deck: DeckViewModel { appModel.deck }
    private var visible: [Product] { Array(deck.cards.prefix(3)) }

    var body: some View {
        VStack(spacing: 16) {
            header

            ZStack {
                if visible.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(visible.enumerated()).reversed(), id: \.element.id) { index, product in
                        SwipeCardView(
                            product: product,
                            state: appModel.tryOn.state(for: product),
                            serviceLabel: appModel.tryOn.serviceLabel,
                            isTop: index == 0,
                            onSwipe: { direction in
                                withAnimation(.snappy) { deck.swipe(product, direction) }
                            },
                            onRetry: { appModel.tryOn.retry(product) }
                        )
                        .scaleEffect(1 - CGFloat(index) * 0.04)
                        .offset(y: CGFloat(index) * 12)
                        .zIndex(Double(-index))
                        .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            buttons
        }
        .padding()
        .task { await deck.loadMoreIfNeeded() }
    }

    private var header: some View {
        HStack {
            Text("Discover").font(.title2.bold())
            Spacer()
            if deck.isLoading {
                ProgressView()
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 40) {
            roundButton(systemImage: "xmark", tint: .red) {
                if let top = deck.cards.first { withAnimation(.snappy) { deck.swipe(top, .left) } }
            }
            roundButton(systemImage: "heart.fill", tint: .green) {
                if let top = deck.cards.first { withAnimation(.snappy) { deck.swipe(top, .right) } }
            }
        }
        .disabled(deck.cards.isEmpty)
    }

    private func roundButton(systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title.bold())
                .foregroundStyle(tint)
                .frame(width: 68, height: 68)
                .background(.background, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var emptyState: some View {
        if deck.isLoading {
            ProgressView("Finding clothes…")
        } else {
            ContentUnavailableView {
                Label("You've seen everything", systemImage: "checkmark.circle")
            } description: {
                Text("Turn on more stores in Settings, or check your liked items.")
            } actions: {
                Button("Start over") {
                    appModel.deck.reset(
                        catalog: ProductCatalog(providers: ProviderRegistry.providers(for: appModel.settings))
                    )
                }
            }
        }
    }
}
