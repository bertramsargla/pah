import SwiftUI

/// Product photo, or drawn placeholder art when there's no photo.
struct ProductImageView: View {
    let product: Product
    var fill = true

    var body: some View {
        if let url = product.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    if fill {
                        image.resizable().scaledToFill()
                    } else {
                        image.resizable().scaledToFit()
                    }
                case .failure:
                    GarmentArtView(category: product.category, hex: product.swatchHex)
                default:
                    ZStack {
                        Retro.panelAlt
                        ProgressView().tint(Retro.ink)
                    }
                }
            }
        } else {
            GarmentArtView(category: product.category, hex: product.swatchHex)
        }
    }
}
