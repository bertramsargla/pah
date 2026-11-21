import SwiftUI
import Observation

/// State for the two-panel wardrobe: which upper and lower garment is showing,
/// the menu-strip section, and the 3-second "play" slideshow of random outfits.
@MainActor
@Observable
final class WardrobeModel {
    private(set) var products: [Product] = []
    private(set) var isLoading = false
    /// Section picked in the bottom strip, or nil for everything ("More").
    private(set) var section: MensSection? = nil
    private(set) var upperIndex = 0
    private(set) var lowerIndex = 0
    private(set) var isPlaying = false
    /// An outfit another screen (the Agent) asked the wardrobe to put on.
    /// The wardrobe screen dresses it as soon as it shows, then clears it.
    var dressRequest: [Product]?

    var playInterval: Duration = .seconds(3)

    @ObservationIgnored private var catalog: ProductCatalog
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var random = SystemRandomNumberGenerator()

    init(catalog: ProductCatalog) {
        self.catalog = catalog
    }

    // MARK: What's showing

    func items(for slot: OutfitSlot) -> [Product] {
        products.filter { product in
            guard OutfitSlot(product.category) == slot else { return false }
            guard let section, section.slot == slot else { return true }
            return MensSection.of(product) == section
        }
    }

    func current(_ slot: OutfitSlot) -> Product? {
        let list = items(for: slot)
        guard !list.isEmpty else { return nil }
        let index = slot == .upper ? upperIndex : lowerIndex
        return list[((index % list.count) + list.count) % list.count]
    }

    /// The outfit Dress Me puts on: upper garment, then lower garment.
    var outfit: [Product] {
        [current(.upper), current(.lower)].compactMap { $0 }
    }

    /// Sections that have at least one item, in menu order.
    var availableSections: [MensSection] {
        let present = Set(products.map(MensSection.of))
        return MensSection.allCases.filter(present.contains)
    }

    // MARK: Loading

    func reset(catalog: ProductCatalog) {
        stop()
        self.catalog = catalog
        products = []
        isLoading = false
        upperIndex = 0
        lowerIndex = 0
        section = nil
        Task { await load() }
    }

    /// Pulls every page from every store (the demo catalog is small).
    func load() async {
        guard !isLoading, products.isEmpty else { return }
        isLoading = true
        let catalog = self.catalog
        var collected: [Product] = []
        for _ in 0..<20 {
            let batch = await catalog.nextBatch()
            collected += batch
            let exhausted = await catalog.isExhausted
            if exhausted || batch.isEmpty { break }
        }
        guard catalog === self.catalog else { return }
        products = collected
        isLoading = false
    }

    // MARK: Buttons

    /// Back / forward buttons: move one item in that panel right away.
    func skip(_ slot: OutfitSlot, by step: Int) {
        switch slot {
        case .upper: upperIndex += step
        case .lower: lowerIndex += step
        }
    }

    /// Shuffle: a random outfit, different from the current one when possible.
    func shuffle() {
        upperIndex = randomIndex(count: items(for: .upper).count, avoiding: upperIndex)
        lowerIndex = randomIndex(count: items(for: .lower).count, avoiding: lowerIndex)
    }

    /// Play: a new random outfit every few seconds until pressed again.
    func togglePlay() {
        isPlaying ? stop() : play()
    }

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        let interval = playInterval
        playTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.shuffle()
            }
        }
    }

    func stop() {
        playTask?.cancel()
        playTask = nil
        isPlaying = false
    }

    /// Turns both panels to these pieces (clearing any section filter) and
    /// returns the outfit now showing.
    @discardableResult
    func show(_ pieces: [Product]) -> [Product] {
        stop()
        section = nil
        for piece in pieces {
            let slot = OutfitSlot(piece.category)
            guard let index = items(for: slot).firstIndex(where: { $0.id == piece.id }) else { continue }
            switch slot {
            case .upper: upperIndex = index
            case .lower: lowerIndex = index
            }
        }
        return outfit
    }

    /// Menu strip: tap a section to show only that kind in its panel; tap it again to clear.
    func select(_ newSection: MensSection?) {
        section = (newSection == section) ? nil : newSection
        if let section {
            switch section.slot {
            case .upper: upperIndex = 0
            case .lower: lowerIndex = 0
            }
        }
    }

    private func randomIndex(count: Int, avoiding current: Int) -> Int {
        guard count > 1 else { return 0 }
        let normalized = ((current % count) + count) % count
        var next = Int.random(in: 0..<count, using: &random)
        if next == normalized { next = (next + 1) % count }
        return next
    }
}
