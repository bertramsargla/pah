import Foundation

enum TryOnBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Free on-device preview. The default, so nothing costs money until you opt in.
    case mock
    /// Paid hosted model on fal.ai.
    case fal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mock: "Preview (free, on device)"
        case .fal: "fal.ai (paid, per image)"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var tryOnBackend: TryOnBackend = .mock
    /// Provider ids the user switched off.
    var disabledStoreIDs: Set<String> = []
    /// Extra Shopify stores to browse, by domain.
    var shopifyDomains: [String] = []
    /// The app's look.
    var skin: Skin = .clueless

    init() {}

    /// Settings saved by an older version may lack newer fields; those get defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        tryOnBackend = try container.decodeIfPresent(TryOnBackend.self, forKey: .tryOnBackend) ?? defaults.tryOnBackend
        disabledStoreIDs = try container.decodeIfPresent(Set<String>.self, forKey: .disabledStoreIDs) ?? defaults.disabledStoreIDs
        shopifyDomains = try container.decodeIfPresent([String].self, forKey: .shopifyDomains) ?? defaults.shopifyDomains
        skin = (try? container.decodeIfPresent(Skin.self, forKey: .skin)) ?? defaults.skin
    }

    private static let key = "app-settings-v1"

    static func load(from defaults: UserDefaults) -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    func save(to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
