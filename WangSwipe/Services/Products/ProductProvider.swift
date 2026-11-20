import Foundation

/// A source of clothing items: a mock catalog, one Shopify store, an affiliate
/// network feed served by your backend, and so on. Add a new store by writing
/// one of these and registering it in `ProviderRegistry`.
protocol ProductProvider: Sendable {
    /// Stable id, used as the prefix of every `Product.id` it returns.
    var id: String { get }
    var displayName: String { get }
    /// Returns one page of products, starting at page 0. An empty array means
    /// the provider has nothing more to show.
    func fetchProducts(page: Int) async throws -> [Product]
}

enum ProductFeedError: LocalizedError {
    case badURL(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badURL(let value): "Not a valid store address: \(value)"
        case .httpStatus(let code): "The store answered with HTTP \(code)."
        }
    }
}
