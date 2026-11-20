import Foundation

/// An in-memory store, used for development and as an example provider.
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

/// Three made-up stores with placeholder art, so the app runs with no network or keys.
enum MockStores {
    static let all: [MockStoreProvider] = [northline, atelierMono, threadAndField]

    static let northline = store(
        id: "mock-northline",
        name: "Northline Supply",
        items: [
            ("Heavyweight Pocket Tee", .top, 28, "#2F4858"),
            ("Waxed Field Jacket", .outerwear, 189, "#5B6B3A"),
            ("Relaxed Carpenter Pant", .bottom, 78, "#8C6A4A"),
            ("Brushed Flannel Shirt", .top, 64, "#9E2A2B"),
            ("Quilted Liner Vest", .outerwear, 98, "#1F2933"),
            ("Selvedge Straight Jean", .bottom, 120, "#22344F"),
            ("Waffle Knit Henley", .top, 42, "#D8C3A5"),
            ("Sherpa Trucker Jacket", .outerwear, 148, "#B08968"),
        ]
    )

    static let atelierMono = store(
        id: "mock-atelier-mono",
        name: "Atelier Mono",
        items: [
            ("Bias Cut Slip Dress", .dress, 145, "#C9A9A6"),
            ("Cropped Boxy Blazer", .outerwear, 210, "#111111"),
            ("Wide Leg Trouser", .bottom, 135, "#E5E0D8"),
            ("Ribbed Mock Neck Top", .top, 58, "#F2F2F2"),
            ("Pleated Midi Skirt", .bottom, 95, "#6D597A"),
            ("Linen Wrap Dress", .dress, 168, "#E9C46A"),
            ("Oversized Poplin Shirt", .top, 88, "#A8DADC"),
            ("Long Wool Coat", .outerwear, 320, "#7F5539"),
        ]
    )

    static let threadAndField = store(
        id: "mock-thread-field",
        name: "Thread & Field",
        items: [
            ("Retro Track Jacket", .outerwear, 85, "#E63946"),
            ("Graphic Crew Sweatshirt", .top, 60, "#457B9D"),
            ("Nylon Cargo Short", .bottom, 48, "#606C38"),
            ("Tie-Dye Tank", .top, 26, "#F4A261"),
            ("Tiered Sundress", .dress, 72, "#FFB4A2"),
            ("Puffer Jacket", .outerwear, 160, "#264653"),
            ("Pull-On Jogger", .bottom, 54, "#3D405B"),
            ("Striped Rugby Polo", .top, 68, "#2A9D8F"),
        ]
    )

    private static func store(
        id: String,
        name: String,
        items: [(String, GarmentCategory, Int, String)]
    ) -> MockStoreProvider {
        let products = items.enumerated().map { index, item in
            Product(
                id: "\(id):\(index)",
                providerID: id,
                storeName: name,
                title: item.0,
                brand: name,
                price: Decimal(item.2),
                currencyCode: "USD",
                category: item.1,
                imageURL: nil,
                productURL: nil,
                swatchHex: item.3
            )
        }
        return MockStoreProvider(id: id, displayName: name, products: products)
    }
}
