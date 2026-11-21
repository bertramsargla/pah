import SwiftUI
import Observation

/// App-wide state: the user's photo, settings, kept items, the wardrobe and the dresser.
@MainActor
@Observable
final class AppModel {
    private(set) var userPhoto: UIImage? = nil
    private(set) var liked: [Product] = []
    private(set) var settings: AppSettings

    let dresser: Dresser
    let wardrobe: WardrobeModel

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let photoStore: PhotoStore

    static let falKeyAccount = "fal-api-key"
    /// The hosted try-on model. Nano Banana dresses the whole outfit in one call and was
    /// the fastest in romeo's side-by-side test (Nov 2026). The other models stay in
    /// `FalTryOnModel` so switching back is a one-line change.
    static let tryOnModel: FalTryOnModel = .nanoBanana
    private static let likedKey = "liked-products-v1"

    init(defaults: UserDefaults = .standard, photoStore: PhotoStore = PhotoStore()) {
        var settings = AppSettings.load(from: defaults)
        // `-skin matrix` (or clueless / doom) as a launch argument shows that skin, for demos and screenshots.
        if let raw = defaults.string(forKey: "skin"), let skin = Skin(rawValue: raw) {
            settings.skin = skin
        }
        self.defaults = defaults
        self.photoStore = photoStore
        self.settings = settings
        Skin.current = settings.skin
        self.dresser = Dresser()
        self.wardrobe = WardrobeModel(
            catalog: ProductCatalog(providers: ProviderRegistry.providers(for: settings))
        )
        self.userPhoto = photoStore.load()
        if let data = defaults.data(forKey: Self.likedKey),
           let saved = try? JSONDecoder().decode([Product].self, from: data) {
            self.liked = saved
        }
        dresser.configure(person: userPhoto, service: makeTryOnService())

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
        dresser.configure(person: prepared, service: makeTryOnService())
    }

    func removePhoto() {
        photoStore.delete()
        userPhoto = nil
        dresser.configure(person: nil, service: makeTryOnService())
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
        Skin.current = next.skin
        settings = next
        next.save(to: defaults)

        if old.tryOnBackend != next.tryOnBackend {
            reloadTryOnService()
        }
        if old.disabledStoreIDs != next.disabledStoreIDs || old.shopifyDomains != next.shopifyDomains {
            wardrobe.reset(catalog: ProductCatalog(providers: ProviderRegistry.providers(for: next)))
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
        dresser.configure(person: userPhoto, service: makeTryOnService())
    }

    /// The one place that decides which try-on implementation the app uses.
    func makeTryOnService() -> any TryOnService {
        switch settings.tryOnBackend {
        case .mock:
            return MockTryOnService()
        case .fal:
            return FalTryOnService(apiKey: KeychainStore.get(Self.falKeyAccount) ?? "", model: Self.tryOnModel)
        }
    }
}
