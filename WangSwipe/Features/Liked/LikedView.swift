import SwiftUI

/// Everything the user swiped right on, newest first, with a link to buy.
struct LikedView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        NavigationStack {
            Group {
                if appModel.liked.isEmpty {
                    ContentUnavailableView(
                        "Nothing liked yet",
                        systemImage: "heart",
                        description: Text("Swipe right on something you'd wear.")
                    )
                } else {
                    List {
                        ForEach(appModel.liked.reversed()) { product in
                            row(product)
                                .swipeActions {
                                    Button("Remove", role: .destructive) { appModel.unlike(product) }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Liked")
        }
    }

    private func row(_ product: Product) -> some View {
        HStack(spacing: 12) {
            thumbnail(product)
                .frame(width: 64, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(product.title).font(.headline).lineLimit(2)
                Text(product.storeName).font(.subheadline).foregroundStyle(.secondary)
                Text(product.formattedPrice).font(.subheadline)
            }

            Spacer()

            if let url = product.productURL {
                Link("Shop", destination: url)
                    .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ product: Product) -> some View {
        if case .ready(let image) = appModel.tryOn.state(for: product) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ProductImageView(product: product)
        }
    }
}
