import Foundation

/// The kind of garment, used to pick a try-on region and placeholder art.
enum GarmentCategory: String, Codable, CaseIterable, Sendable {
    case top
    case bottom
    case dress
    case outerwear

    var displayName: String {
        switch self {
        case .top: "Top"
        case .bottom: "Bottom"
        case .dress: "Dress"
        case .outerwear: "Outerwear"
        }
    }

    var pluralName: String {
        switch self {
        case .top: "Tops"
        case .bottom: "Bottoms"
        case .dress: "Dresses"
        case .outerwear: "Outerwear"
        }
    }

    /// Best-effort guess from free text such as a store's product type or title.
    /// Returns nil when the text doesn't look like clothing we can try on.
    static func infer(from text: String) -> GarmentCategory? {
        let tokens = Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.letters.inverted)
                .filter { !$0.isEmpty }
        )
        let keywords: [(GarmentCategory, Set<String>)] = [
            (.dress, ["dress", "dresses", "jumpsuit", "romper", "gown"]),
            (.outerwear, ["jacket", "jackets", "coat", "coats", "blazer", "parka", "anorak", "overshirt", "outerwear"]),
            (.bottom, ["pants", "pant", "jeans", "shorts", "skirt", "skirts", "trousers", "leggings", "chinos", "joggers", "sweatpants", "bottoms"]),
            (.top, ["shirt", "shirts", "tee", "tees", "tshirt", "top", "tops", "sweater", "hoodie", "sweatshirt", "blouse", "polo", "tank", "cardigan", "crewneck", "henley", "knit"]),
        ]
        for (category, words) in keywords where !tokens.isDisjoint(with: words) {
            return category
        }
        return nil
    }
}

/// One clothing item from any store provider, normalized to a common shape.
struct Product: Identifiable, Hashable, Codable, Sendable {
    /// Globally unique: "<providerID>:<item id>".
    let id: String
    let providerID: String
    let storeName: String
    let title: String
    let brand: String?
    let price: Decimal
    let currencyCode: String
    let category: GarmentCategory
    /// Photo of the garment. Try-on works best with a flat-lay or ghost-mannequin shot.
    let imageURL: URL?
    /// Where the user can buy it (an affiliate link in production).
    let productURL: URL?
    /// Used to draw placeholder art when there is no image (mock data).
    let swatchHex: String?

    var formattedPrice: String {
        price.formatted(.currency(code: currencyCode))
    }
}

/// Where a garment goes in the two-panel wardrobe.
enum OutfitSlot: Sendable {
    case upper  // shirts, sweaters, jackets
    case lower  // pants, jeans

    init(_ category: GarmentCategory) {
        switch category {
        case .top, .outerwear, .dress: self = .upper
        case .bottom: self = .lower
        }
    }
}

/// Menswear sections for the wardrobe's bottom menu strip.
enum MensSection: String, CaseIterable, Identifiable, Sendable {
    case shirts, sweaters, jackets, pants, jeans

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    var slot: OutfitSlot {
        switch self {
        case .shirts, .sweaters, .jackets: .upper
        case .pants, .jeans: .lower
        }
    }

    static func of(_ product: Product) -> MensSection {
        let words = Set(product.title.lowercased().components(separatedBy: CharacterSet.letters.inverted))
        switch product.category {
        case .outerwear:
            return .jackets
        case .bottom:
            return words.isDisjoint(with: ["jean", "jeans", "denim"]) ? .pants : .jeans
        case .top, .dress:
            return words.isDisjoint(with: ["sweater", "sweaters", "knit", "cardigan", "jumper", "crewneck"]) ? .shirts : .sweaters
        }
    }
}
