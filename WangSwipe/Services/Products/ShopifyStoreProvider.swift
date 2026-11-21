import Foundation

/// Reads a Shopify store's public `/products.json` listing. Many Shopify
/// storefronts serve it without a key, but some turn it off, and each store's
/// terms apply. For a real launch, prefer an affiliate feed or a partnership
/// (see docs/PROVIDERS.md); this provider is for prototyping with stores you
/// have permission to use.
struct ShopifyStoreProvider: ProductProvider {
    /// Store domain, for example "example-store.myshopify.com".
    let domain: String
    var currencyCode = "USD"
    var pageSize = 20
    var session: URLSession = .shared

    var id: String { "shopify:\(domain)" }
    var displayName: String { domain }

    func fetchProducts(page: Int) async throws -> [Product] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        components.path = "/products.json"
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "page", value: String(page + 1)),
        ]
        guard let url = components.url else { throw ProductFeedError.badURL(domain) }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ProductFeedError.httpStatus(http.statusCode)
        }
        return try Self.parse(data, domain: domain, providerID: id, currencyCode: currencyCode)
    }

    /// Maps Shopify's JSON to `Product`, dropping items that aren't clothing we can try on.
    static func parse(_ data: Data, domain: String, providerID: String, currencyCode: String) throws -> [Product] {
        let listing = try JSONDecoder().decode(Listing.self, from: data)
        return listing.products.compactMap { item in
            let typeText = [item.productType, item.title].compactMap { $0 }.joined(separator: " ")
            guard
                let category = GarmentCategory.infer(from: typeText),
                let priceText = item.variants.first?.price,
                let price = Decimal(string: priceText)
            else { return nil }

            return Product(
                id: "\(providerID):\(item.id)",
                providerID: providerID,
                storeName: domain,
                title: item.title,
                brand: item.vendor,
                price: price,
                currencyCode: currencyCode,
                category: category,
                imageURL: item.images.first.flatMap { URL(string: $0.src) },
                productURL: URL(string: "https://\(domain)/products/\(item.handle)"),
                swatchHex: nil
            )
        }
    }

    private struct Listing: Decodable {
        let products: [Item]
    }

    private struct Item: Decodable {
        let id: Int
        let title: String
        let handle: String
        let vendor: String?
        let productType: String?
        let variants: [Variant]
        let images: [Image]

        enum CodingKeys: String, CodingKey {
            case id, title, handle, vendor, variants, images
            case productType = "product_type"
        }
    }

    private struct Variant: Decodable {
        let price: String
    }

    private struct Image: Decodable {
        let src: String
    }
}
