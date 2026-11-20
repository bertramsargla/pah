import SwiftUI

/// Everything the user swiped right on, newest first, with a link to buy.
struct LikedView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(title: "My Closet")

            ZStack {
                LeopardPattern()

                if appModel.liked.isEmpty {
                    RetroPanel(padding: 20) {
                        VStack(spacing: 8) {
                            Text("Closet's empty").font(Retro.font(20))
                            Text("Hit Dress Me on something you'd wear.").font(Retro.font(13, weight: .medium))
                        }
                        .textCase(.uppercase)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Retro.ink)
                    }
                    .padding(24)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(appModel.liked.reversed()) { product in
                                row(product)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .overlay(Scanlines())
    }

    private func row(_ product: Product) -> some View {
        RetroPanel(padding: 8) {
            HStack(spacing: 10) {
                thumbnail(product)
                    .frame(width: 72, height: 96)
                    .clipped()
                    .overlay(Rectangle().stroke(Retro.ink, lineWidth: 1.5))

                VStack(alignment: .leading, spacing: 3) {
                    Text(product.title).font(Retro.font(14)).lineLimit(2)
                    Text([product.brand, product.storeName].compactMap { $0 }.joined(separator: " · ")).font(Retro.font(11, weight: .bold)).opacity(0.7)
                    Text(product.formattedPrice).font(Retro.font(13, weight: .bold))
                }
                .textCase(.uppercase)
                .foregroundStyle(Retro.ink)

                Spacer(minLength: 0)

                VStack(spacing: 8) {
                    if let url = product.productURL {
                        Link(destination: url) { Text("Shop").padding(.horizontal, 4) }
                            .buttonStyle(BevelButtonStyle(size: 12))
                    }
                    Button("Toss") { withAnimation { appModel.unlike(product) } }
                        .buttonStyle(BevelButtonStyle(size: 12))
                }
                .frame(width: 76)
            }
        }
    }

    private func thumbnail(_ product: Product) -> some View {
        ProductImageView(product: product)
    }
}
