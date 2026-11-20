import Foundation

/// Hand-picked men's pieces from FWRD and Grailed for the demo, collected
/// November 20, 2026. Images are loaded from each store's CDN and the Shop
/// link opens the real product page. Prices and stock change: Grailed items
/// are one-off resale listings and can sell at any time.
enum CuratedStores {
    static let all: [MockStoreProvider] = [fwrd, grailed]

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
            Item("MUIF-MS111", "University T-shirt", "Museum of Peace and Quiet", 48, .top,
                 image: "https://is8.fwrdassets.com/images/p/fw/z/MUIF-MS111_V1.jpg",
                 link: "https://www.fwrd.com/product-museum-of-peace-and-quiet-university-tshirt-in-white/MUIF-MS111/?d=Mens"),
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
            Item("112475358", "Leather Jacket", "Human Made", 450, .outerwear,
                 image: "https://media-assets.grailed.com/prd/listing/5475363/214bf3e39ad24544aebb8ed898591caa?w=1000",
                 link: "https://www.grailed.com/listings/112475358-human-made-human-made-leather-jacket"),
            Item("112402693", "Crash Sweater", "Visvim", 540, .top,
                 image: "https://media-assets.grailed.com/prd/listing/47549946/1236e285c5254e0c8452747f03cf61cc?w=1000",
                 link: "https://www.grailed.com/listings/112402693-visvim-visvim-crash-sweater"),
            Item("107361561", "Brown Coated Denim Waxed Curved Jeans", "Acne Studios", 291, .bottom,
                 image: "https://media-assets.grailed.com/prd/listing/temp/b091ad3b8de24e93aacab4b0779efbbe?w=1000",
                 link: "https://www.grailed.com/listings/107361561-acne-studios-brown-coated-denim-waxed-curved-jeans"),
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
