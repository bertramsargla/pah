import SwiftUI
import Observation

enum SwipeDirection: Equatable {
    case left   // pass
    case right  // like

    /// Decides whether a drag should count as a swipe. A fast flick counts
    /// even if it didn't travel past the threshold.
    static func decide(translation: CGSize, predictedEnd: CGSize, threshold: CGFloat) -> SwipeDirection? {
        let distance = abs(translation.width) >= threshold ? translation.width : predictedEnd.width
        if distance >= threshold { return .right }
        if distance <= -threshold { return .left }
        return nil
    }
}

/// The card stack: loads products from the catalog as the user swipes and
/// asks the try-on runner to prepare the next few cards.
@MainActor
@Observable
final class DeckViewModel {
    private(set) var cards: [Product] = []
    private(set) var isLoading = false
    private(set) var isExhausted = false
    /// Only show this kind of garment, or everything when nil.
    private(set) var categoryFilter: GarmentCategory? = nil

    /// Cards that match the current filter, in deck order.
    var visibleCards: [Product] {
        guard let categoryFilter else { return cards }
        return cards.filter { $0.category == categoryFilter }
    }

    /// How many cards ahead to prepare try-ons for.
    var lookahead = 3
    @ObservationIgnored var onLike: (Product) -> Void = { _ in }

    @ObservationIgnored private var catalog: ProductCatalog
    private let tryOn: TryOnCoordinator

    init(catalog: ProductCatalog, tryOn: TryOnCoordinator) {
        self.catalog = catalog
        self.tryOn = tryOn
    }

    func reset(catalog: ProductCatalog) {
        self.catalog = catalog
        cards = []
        isExhausted = false
        isLoading = false
        Task { await loadMoreIfNeeded() }
    }

    func loadMoreIfNeeded() async {
        defer { refreshTryOns() }
        guard !isLoading, !isExhausted, visibleCards.count < 6 else { return }
        isLoading = true
        let catalog = self.catalog
        let batch = await catalog.nextBatch()
        let exhausted = await catalog.isExhausted
        guard catalog === self.catalog else { return }  // settings changed while loading
        isLoading = false
        let existing = Set(cards.map(\.id))
        let fresh = batch.filter { !existing.contains($0.id) }
        cards.append(contentsOf: fresh)
        isExhausted = batch.isEmpty && exhausted
        if batch.isEmpty && !exhausted { return }  // a store errored; wait for the next swipe
        if visibleCards.count < 6 { await loadMoreIfNeeded() }
    }

    func swipe(_ product: Product, _ direction: SwipeDirection) {
        cards.removeAll { $0.id == product.id }
        if direction == .right { onLike(product) }
        Task { await loadMoreIfNeeded() }
    }

    func setFilter(_ category: GarmentCategory?) {
        categoryFilter = category
        Task { await loadMoreIfNeeded() }
    }

    func refreshTryOns() {
        tryOn.request(Array(visibleCards.prefix(lookahead)))
    }
}
