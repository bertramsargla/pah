import SwiftUI
import Observation

/// App-wide state: the user's photo, settings, kept items, the wardrobe and the dresser.
@MainActor
@Observable
final class AppModel {
    private(set) var userPhoto: UIImage? = nil
    private(set) var liked: [Product] = []
    /// The tab showing; the Agent's Dress Me switches it to the wardrobe.
    var tab: MainTab = .wardrobe
    private(set) var settings: AppSettings

    let dresser: Dresser
    let wardrobe: WardrobeModel
    let agent = AgentModel()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let photoStore: PhotoStore

    static let falKeyAccount = "fal-api-key"
    static let geminiKeyAccount = "gemini-api-key"
    static let sensoKeyAccount = "senso-api-key"
    /// Which version of each document is filed in Senso: title -> "fingerprint|node id".
    private static let sensoFiledKey = "senso-filed-v1"
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

        #if DEBUG
        // `-agentDemo YES` opens the Agent tab on a canned outfit pick, for screenshots
        // of its Dress Me button without a paid Gemini call.
        if defaults.bool(forKey: "agentDemo") {
            let pieces = CuratedStores.all.flatMap(\.products)
            if let top = pieces.first(where: { OutfitSlot($0.category) == .upper }),
               let bottom = pieces.first(where: { OutfitSlot($0.category) == .lower }) {
                agent.showDemo(question: "Find me the perfect match", reply: """
                    Go with the \(top.brand ?? top.storeName) \(top.title) and the \(bottom.brand ?? bottom.storeName) \(bottom.title). (Canned demo reply.)
                    OUTFIT: \(top.id) | \(bottom.id)
                    """)
                tab = .agent
            }
        }
        #endif
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

    var geminiAPIKey: String {
        KeychainStore.get(Self.geminiKeyAccount) ?? ""
    }

    /// Observable mirror of whether a key is saved, so screens update when one is added.
    private(set) var hasGeminiKey = !(KeychainStore.get(AppModel.geminiKeyAccount) ?? "").isEmpty

    func setGeminiAPIKey(_ key: String) {
        KeychainStore.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: Self.geminiKeyAccount)
        hasGeminiKey = !geminiAPIKey.isEmpty
    }

    // MARK: Senso knowledge base

    var sensoAPIKey: String { Self.storedSensoKey }

    private static var storedSensoKey: String {
        if let key = KeychainStore.get(sensoKeyAccount), !key.isEmpty { return key }
        #if DEBUG
        // Debug builds can take the key from the launch environment (SIMCTL_CHILD_SENSO_API_KEY
        // with simctl), so a demo machine can use Senso without typing the key into Setup.
        return ProcessInfo.processInfo.environment["SENSO_API_KEY"] ?? ""
        #else
        return ""
        #endif
    }

    private(set) var hasSensoKey = !AppModel.storedSensoKey.isEmpty
    /// The outcome of the last filing, shown in Setup.
    private(set) var sensoStatus: String?
    @ObservationIgnored private var isFilingInSenso = false

    /// The knowledge-base client, when a Senso key is saved.
    var senso: SensoClient? {
        hasSensoKey ? SensoClient(apiKey: sensoAPIKey) : nil
    }

    func setSensoAPIKey(_ key: String) {
        KeychainStore.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: Self.sensoKeyAccount)
        hasSensoKey = !sensoAPIKey.isEmpty
        sensoStatus = nil
        defaults.removeObject(forKey: Self.sensoFiledKey)
        Task {
            await wardrobe.load()
            await fileInSenso()
        }
    }

    /// Files the style guide and the current wardrobe in Senso, skipping any document
    /// already filed in this exact version, and removing the copy it replaces.
    func fileInSenso() async {
        guard let senso, !isFilingInSenso, !wardrobe.products.isEmpty else { return }
        isFilingInSenso = true
        defer { isFilingInSenso = false }
        var filed = defaults.dictionary(forKey: Self.sensoFiledKey) as? [String: String] ?? [:]
        let documents = [
            (SensoClient.styleGuideTitle, StyleGuide.text),
            (SensoClient.wardrobeTitle, SensoClient.wardrobeDocument(wardrobe.products))
        ]
        do {
            var changed = false
            for (title, text) in documents {
                let fingerprint = SensoClient.fingerprint(text)
                let previous = (filed[title] ?? "").split(separator: "|").map(String.init)
                if previous.first == fingerprint { continue }
                var entry = fingerprint
                let result = try await senso.file(title: title, text: text)
                if case .accepted(let nodeID?) = result {
                    entry += "|" + nodeID
                    if previous.count > 1, previous[1] != nodeID {
                        try? await senso.remove(nodeID: previous[1])
                    }
                }
                filed[title] = entry
                defaults.set(filed, forKey: Self.sensoFiledKey)
                changed = true
            }
            if changed || sensoStatus == nil {
                sensoStatus = "Style guide and wardrobe are filed in Senso."
            }
        } catch {
            sensoStatus = error.localizedDescription
        }
    }

    /// What the Agent tab's stylist gets to see.
    /// The Agent's Dress Me: go to the wardrobe and try on the agent's pick.
    func dressInWardrobe(_ pieces: [Product]) {
        guard !pieces.isEmpty else { return }
        wardrobe.dressRequest = pieces
        tab = .wardrobe
    }

    func stylistContext() -> StylistContext {
        let showing = wardrobe.outfit
        var look: UIImage?
        if case .ready(let image) = dresser.state(for: showing) { look = image }
        return StylistContext(wardrobe: wardrobe.products, showing: showing, kept: liked, photo: userPhoto, look: look)
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
