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
    var falModel: FalTryOnModel = .googleVTO
    /// Provider ids the user switched off.
    var disabledStoreIDs: Set<String> = []
    /// Extra Shopify stores to browse, by domain.
    var shopifyDomains: [String] = []

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
