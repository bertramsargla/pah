import Foundation

/// Builds the list of active store providers from the user's settings.
enum ProviderRegistry {
    static func providers(for settings: AppSettings) -> [any ProductProvider] {
        let mocks: [any ProductProvider] = MockStores.all.filter { !settings.disabledStoreIDs.contains($0.id) }
        let shopify: [any ProductProvider] = settings.shopifyDomains
            .map { ShopifyStoreProvider(domain: $0) }
            .filter { !settings.disabledStoreIDs.contains($0.id) }
        return mocks + shopify
    }
}
