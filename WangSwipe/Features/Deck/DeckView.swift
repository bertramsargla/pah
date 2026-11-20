import SwiftUI

/// The main screen, styled as a 90s wardrobe computer: title bar, leopard
/// print around a display panel, big beveled buttons, and a category strip.
struct DeckView: View {
    @Environment(AppModel.self) private var appModel

    private var deck: DeckViewModel { appModel.deck }
    private var visible: [Product] { Array(deck.visibleCards.prefix(3)) }

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(title: "Fall Fashions")

            ZStack {
                LeopardPattern()

                VStack(spacing: 14) {
                    cardStack
                        .padding(.horizontal, 22)
                        .padding(.top, 16)

                    buttons
                        .padding(.horizontal, 22)
                        .padding(.bottom, 14)
                }
            }

            CategoryStrip(selected: deck.categoryFilter) { category in
                withAnimation(.snappy) { deck.setFilter(category) }
            }
        }
        .overlay(Scanlines())
        .task { await deck.loadMoreIfNeeded() }
    }

    private var cardStack: some View {
        ZStack {
            if visible.isEmpty {
                RetroPanel { emptyState.frame(maxWidth: .infinity, maxHeight: .infinity) }
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
                    .offset(x: CGFloat(index) * 4, y: CGFloat(index) * 6)
                    .zIndex(Double(-index))
                    .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var buttons: some View {
        HStack(spacing: 16) {
            Button {
                if let top = deck.visibleCards.first { withAnimation(.snappy) { deck.swipe(top, .left) } }
            } label: {
                Label("Pass", systemImage: "xmark")
            }
            .buttonStyle(BevelButtonStyle(size: 22))

            Button {
                if let top = deck.visibleCards.first { withAnimation(.snappy) { deck.swipe(top, .right) } }
            } label: {
                Text("Dress Me")
            }
            .buttonStyle(.bevelPrimary)
        }
        .frame(height: 64)
        .disabled(deck.visibleCards.isEmpty)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 14) {
            if deck.isLoading {
                ProgressView().tint(Retro.navy)
                Text("Loading wardrobe…").font(Retro.font(16))
            } else {
                Text(deck.categoryFilter == nil ? "That's the whole wardrobe" : "No more \(deck.categoryFilter!.displayName.lowercased())s")
                    .font(Retro.font(18))
                    .multilineTextAlignment(.center)
                Text("Turn on more stores in Setup, or check your closet.")
                    .font(Retro.font(13, weight: .medium))
                    .multilineTextAlignment(.center)
                Button("Start over") {
                    deck.reset(catalog: ProductCatalog(providers: ProviderRegistry.providers(for: appModel.settings)))
                }
                .buttonStyle(.bevel)
                .frame(width: 200)
            }
        }
        .foregroundStyle(Retro.ink)
        .textCase(.uppercase)
        .padding()
    }
}

/// Bottom strip of garment categories, like the wardrobe's menu bar. Tapping one filters the deck.
struct CategoryStrip: View {
    let selected: GarmentCategory?
    var onSelect: (GarmentCategory?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            item("All", isOn: selected == nil) { onSelect(nil) }
            ForEach(GarmentCategory.allCases, id: \.self) { category in
                item(category.displayName + "s", isOn: selected == category) { onSelect(category) }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(Retro.navy)
    }

    private func item(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Retro.font(12, weight: .bold))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(isOn ? Retro.navy : Retro.lavender)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(isOn ? Retro.lavender : .clear)
        }
        .buttonStyle(.plain)
    }
}
