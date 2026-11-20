import SwiftUI
import Observation

/// App-wide state: the user's photo, settings, liked items, the deck and try-on runner.
@MainActor
@Observable
final class AppModel {
    private(set) var userPhoto: UIImage? = nil
    private(set) var liked: [Product] = []
    private(set) var settings: AppSettings

    let tryOn: TryOnCoordinator
    let deck: DeckViewModel

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let photoStore: PhotoStore

    static let falKeyAccount = "fal-api-key"
    private static let likedKey = "liked-products-v1"

    init(defaults: UserDefaults = .standard, photoStore: PhotoStore = PhotoStore()) {
        let settings = AppSettings.load(from: defaults)
        let tryOn = TryOnCoordinator()
        self.defaults = defaults
        self.photoStore = photoStore
        self.settings = settings
        self.tryOn = tryOn
        self.deck = DeckViewModel(
            catalog: ProductCatalog(providers: ProviderRegistry.providers(for: settings)),
            tryOn: tryOn
        )
        self.userPhoto = photoStore.load()
        if let data = defaults.data(forKey: Self.likedKey),
           let saved = try? JSONDecoder().decode([Product].self, from: data) {
            self.liked = saved
        }
        deck.lookahead = settings.tryOnBackend == .fal ? 2 : 3
        tryOn.configure(person: userPhoto, service: makeTryOnService())
        deck.onLike = { [weak self] product in self?.like(product) }

        // `-demoMode YES` as a launch argument skips onboarding with the demo photo.
        if userPhoto == nil, defaults.bool(forKey: "demoMode"), let demo = Self.demoPhoto {
            setPhoto(demo)
        }
    }

    /// The bundled sample photo, so the app can be shown without taking one.
    nonisolated static var demoPhoto: UIImage? { UIImage(named: "DemoPerson") }

    // MARK: Photo

    func setPhoto(_ image: UIImage) {
        let prepared = image.normalizedUp().resized(maxDimension: 1536)
        try? photoStore.save(prepared)
        userPhoto = prepared
        tryOn.configure(person: prepared, service: makeTryOnService())
        deck.refreshTryOns()
    }

    func removePhoto() {
        photoStore.delete()
        userPhoto = nil
        tryOn.configure(person: nil, service: makeTryOnService())
    }

    // MARK: Likes

    func like(_ product: Product) {
        guard !liked.contains(where: { $0.id == product.id }) else { return }
        liked.append(product)
        saveLiked()
    }

    func unlike(_ product: Product) {
        liked.removeAll { $0.id == product.id }
        saveLiked()
    }

    private func saveLiked() {
        if let data = try? JSONEncoder().encode(liked) {
            defaults.set(data, forKey: Self.likedKey)
        }
    }

    // MARK: Settings

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        let old = settings
        settings = next
        next.save(to: defaults)

        if old.tryOnBackend != next.tryOnBackend || old.falModel != next.falModel {
            reloadTryOnService()
        }
        if old.disabledStoreIDs != next.disabledStoreIDs || old.shopifyDomains != next.shopifyDomains {
            deck.reset(catalog: ProductCatalog(providers: ProviderRegistry.providers(for: next)))
        }
    }

    /// Two-way binding into one settings field, for forms.
    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in self.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }

    var falAPIKey: String {
        KeychainStore.get(Self.falKeyAccount) ?? ""
    }

    func setFalAPIKey(_ key: String) {
        KeychainStore.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: Self.falKeyAccount)
        reloadTryOnService()
    }

    private func reloadTryOnService() {
        // Paid calls: prepare fewer cards ahead so skipped cards cost less.
        deck.lookahead = settings.tryOnBackend == .fal ? 2 : 3
        tryOn.configure(person: userPhoto, service: makeTryOnService())
        deck.refreshTryOns()
    }

    /// The one place that decides which try-on implementation the app uses.
    func makeTryOnService() -> any TryOnService {
        switch settings.tryOnBackend {
        case .mock:
            return MockTryOnService()
        case .fal:
            return FalTryOnService(apiKey: KeychainStore.get(Self.falKeyAccount) ?? "", model: settings.falModel)
        }
    }
}
