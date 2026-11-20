import SwiftUI

/// One draggable card. Shows the try-on result when it's ready, otherwise the
/// product photo with a progress badge. Tap to flip between "on you" and the original.
struct SwipeCardView: View {
    let product: Product
    let state: TryOnCoordinator.State
    let serviceLabel: String
    let isTop: Bool
    var onSwipe: (SwipeDirection) -> Void
    var onRetry: () -> Void

    @State private var offset: CGSize = .zero
    @State private var showOriginal = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                imageLayer
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)

                info
            }
            .overlay(alignment: .topLeading) { statusBadge.padding(12) }
            .overlay(alignment: .top) { stamps.padding(.top, 40) }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            .offset(offset)
            .rotationEffect(.degrees(Double(offset.width / 20)), anchor: .bottom)
            .contentShape(Rectangle())
            .onTapGesture { if case .ready = state { showOriginal.toggle() } }
            .gesture(drag(cardWidth: geo.size.width), including: isTop ? .all : .subviews)
        }
    }

    // MARK: Layers

    @ViewBuilder
    private var imageLayer: some View {
        if case .ready(let image) = state, !showOriginal {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ProductImageView(product: product)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(product.storeName.uppercased())
                .font(.caption.weight(.semibold))
                .opacity(0.8)
            Text(product.title)
                .font(.title2.bold())
                .lineLimit(2)
            HStack {
                Text(product.formattedPrice).font(.headline)
                Text("· \(product.category.displayName)").font(.subheadline).opacity(0.8)
                Spacer()
                if let url = product.productURL {
                    Link(destination: url) {
                        Image(systemName: "bag").font(.headline)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch state {
        case .idle:
            EmptyView()
        case .working:
            badge {
                ProgressView().controlSize(.small).tint(.white)
                Text("Putting it on you…")
            }
        case .ready:
            badge {
                Image(systemName: showOriginal ? "photo" : "person.fill.checkmark")
                Text(showOriginal ? "Original · tap to try on" : "\(serviceLabel) · tap for original")
            }
        case .failed(let message):
            Button(action: onRetry) {
                badge {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Try-on failed · retry")
                }
            }
            .accessibilityHint(message)
        }
    }

    private func badge<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6, content: content)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())
    }

    private var stamps: some View {
        let progress = min(abs(offset.width) / 120, 1)
        return ZStack {
            stamp("LIKE", color: .green, angle: -15)
                .opacity(offset.width > 0 ? progress : 0)
            stamp("NOPE", color: .red, angle: 15)
                .opacity(offset.width < 0 ? progress : 0)
        }
    }

    private func stamp(_ text: String, color: Color, angle: Double) -> some View {
        Text(text)
            .font(.system(size: 40, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(angle))
    }

    // MARK: Gesture

    private func drag(cardWidth: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in offset = value.translation }
            .onEnded { value in
                let direction = SwipeDirection.decide(
                    translation: value.translation,
                    predictedEnd: value.predictedEndTranslation,
                    threshold: cardWidth * 0.3
                )
                guard let direction else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { offset = .zero }
                    return
                }
                let exitX = (direction == .right ? 1.5 : -1.5) * cardWidth
                withAnimation(.easeOut(duration: 0.2)) {
                    offset = CGSize(width: exitX, height: value.translation.height)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onSwipe(direction) }
            }
    }
}

/// Product photo, or drawn placeholder art when there's no photo.
struct ProductImageView: View {
    let product: Product

    var body: some View {
        if let url = product.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    GarmentArtView(category: product.category, hex: product.swatchHex)
                default:
                    ZStack {
                        Color(white: 0.92)
                        ProgressView()
                    }
                }
            }
        } else {
            GarmentArtView(category: product.category, hex: product.swatchHex)
        }
    }
}
