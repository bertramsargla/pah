import Foundation

/// Hand-picked men's pieces from FWRD, Grailed and Farfetch for the demo, collected
/// November 20, 2026. Images are loaded from each store's CDN and the Shop
/// link opens the real product page. Prices and stock change: Grailed items
/// are one-off resale listings and can sell at any time.
enum CuratedStores {
    static let all: [MockStoreProvider] = [fwrd, grailed, farfetch]

    static let fwrd = store(
        id: "fwrd",
        name: "FWRD",
        items: [
            Item("MONC-MO233", "Rigel Biker Jacket", "Moncler", 1810, .outerwear,
                 image: "https://is8.fwrdassets.com/images/p/fw/z/MONC-MO233_V1.jpg",
                 link: "https://www.fwrd.com/product-moncler-rigel-biker-jacket-in-black/MONC-MO233/?d=Mens"),
            Item("MONC-MS150", "Shirt in Cosmic Blue", "Moncler", 995, .top,
                 image: "https://is8.fwrdassets.com/images/p/fw/z/MONC-MS150_V1.jpg",
                 link: "https://www.fwrd.com/product-moncler-shirt-in-cosmic-blue/MONC-MS150/?d=Mens"),
            Item("BBOU-MO45", "Icons Bedale Wax Jacket", "Barbour", 460, .outerwear,
                 image: "https://is8.fwrdassets.com/images/p/fw/z/BBOU-MO45_V1.jpg",
                 link: "https://www.fwrd.com/product-barbour-icons-bedale-wax-jacket-in-brown/BBOU-MO45/?d=Mens"),
            Item("LEIV-MS64", "Union Rugby Shirt", "Levi's", 55, .top,
                 image: "https://is8.fwrdassets.com/images/p/fw/z/LEIV-MS64_V1.jpg",
                 link: "https://www.fwrd.com/product-levis-union-rugby-shirt-in-amos-stripe-ponderosa-pine/LEIV-MS64/?d=Mens"),
        ]
    )

    static let grailed = store(
        id: "grailed",
        name: "Grailed",
        items: [
            Item("112839243", "Arc Logo Denim Hooded Chore Jacket FW17", "Supreme", 250, .outerwear,
                 image: "https://media-assets.grailed.com/prd/listing/temp/de2c9512246746dd86ca50a13f0bf946?w=1000",
                 link: "https://www.grailed.com/listings/112839243-supreme-supreme-arc-logo-denim-hooded-chore-jacket-fw17"),
            Item("112555406", "Blood Red Button Up Shirt", "Issey Miyake", 150, .top,
                 image: "https://media-assets.grailed.com/prd/listing/temp/8bcf4f622d9c4ed1983739002864cee8?w=1000",
                 link: "https://www.grailed.com/listings/112555406-issey-miyake-blood-red-button-up-shirt"),
            Item("107361561", "Brown Coated Denim Waxed Curved Jeans", "Acne Studios", 291, .bottom,
                 image: "https://media-assets.grailed.com/prd/listing/temp/b091ad3b8de24e93aacab4b0779efbbe?w=1000",
                 link: "https://www.grailed.com/listings/107361561-acne-studios-brown-coated-denim-waxed-curved-jeans"),
        ]
    )

    static let farfetch = store(
        id: "farfetch",
        name: "Farfetch",
        items: [
            Item("40869644", "Silk Satin Bomber", "Tom Ford", 5250, .outerwear,
                 image: "https://cdn-images.farfetch-contents.com/40/86/96/44/40869644_99140328_1000.jpg",
                 link: "https://www.farfetch.com/shopping/men/tom-ford-silk-satin-bomber-item-40869644.aspx"),
            Item("40953097", "The Chalet Sweater", "Jacquemus", 891, .top,
                 image: "https://cdn-images.farfetch-contents.com/40/95/30/97/40953097_99243163_1000.jpg",
                 link: "https://www.farfetch.com/shopping/men/jacquemus-the-chalet-sweater-item-40953097.aspx"),
            // On sale: $296 originally, $260 sale price (before Farfetch's extra promo code).
            Item("40357964", "2001 D-Macro Distressed Straight-Leg Jeans", "Diesel", 260, .bottom,
                 image: "https://cdn-images.farfetch-contents.com/40/35/79/64/40357964_98525689_1000.jpg",
                 link: "https://www.farfetch.com/shopping/men/diesel-2001-d-macro-distressed-straight-leg-jeans-item-40357964.aspx"),
        ]
    )

    /// Categories the menswear demo uses (no dresses).
    static let categories: [GarmentCategory] = [.top, .outerwear, .bottom]

    struct Item {
        let sku: String
        let title: String
        let brand: String
        let price: Int
        let category: GarmentCategory
        let image: String
        let link: String

        init(_ sku: String, _ title: String, _ brand: String, _ price: Int, _ category: GarmentCategory,
             image: String, link: String) {
            self.sku = sku
            self.title = title
            self.brand = brand
            self.price = price
            self.category = category
            self.image = image
            self.link = link
        }
    }

    private static func store(id: String, name: String, items: [Item]) -> MockStoreProvider {
        let products = items.map { item in
            Product(
                id: "\(id):\(item.sku)",
                providerID: id,
                storeName: name,
                title: item.title,
                brand: item.brand,
                price: Decimal(item.price),
                currencyCode: "USD",
                category: item.category,
                imageURL: URL(string: item.image),
                productURL: URL(string: item.link),
                swatchHex: nil
            )
        }
        return MockStoreProvider(id: id, displayName: name, products: products, pageSize: 3, latency: .zero)
    }
}
