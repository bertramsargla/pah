import Foundation

/// An in-memory store: the curated demo catalog, and tests.
struct MockStoreProvider: ProductProvider {
    let id: String
    let displayName: String
    let products: [Product]
    var pageSize = 4
    /// Simulated network delay.
    var latency: Duration = .milliseconds(250)

    func fetchProducts(page: Int) async throws -> [Product] {
        try await Task.sleep(for: latency)
        let start = page * pageSize
        guard page >= 0, start < products.count else { return [] }
        return Array(products[start..<min(start + pageSize, products.count)])
    }
}
