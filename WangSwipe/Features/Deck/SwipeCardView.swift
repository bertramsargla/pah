import SwiftUI

/// One draggable card in a sunken display panel. Shows the try-on result when
/// it's ready, otherwise the product photo with a status tag. Tap to flip
/// between "on you" and the original.
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
            VStack(spacing: 0) {
                // Color.clear takes exactly the space offered; the image fills it
                // without pushing the layout bigger.
                Retro.periwinkle
                    .overlay { imageLayer }
                    .clipped()
                .overlay(Rectangle().stroke(Retro.ink, lineWidth: 2))
                .overlay(alignment: .topLeading) { statusTag.padding(8) }
                .overlay(alignment: .top) { stamps.padding(.top, 36) }

                info
            }
            .padding(10)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Retro.lavender)
            .overlay(Bevel(raised: true, width: 4))
            .overlay(Rectangle().stroke(Retro.ink, lineWidth: 2))
            .background(Rectangle().fill(.black.opacity(0.35)).offset(x: 5, y: 5))
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
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.storeName)
                    .font(Retro.font(11, weight: .bold))
                    .opacity(0.7)
                Text(product.title)
                    .font(Retro.font(17))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text("\(product.formattedPrice) · \(product.category.displayName)")
                    .font(Retro.font(14, weight: .bold))
            }
            Spacer(minLength: 0)
            if let url = product.productURL {
                Link(destination: url) {
                    Text("Shop")
                        .font(Retro.font(13))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Retro.buttonGray)
                        .overlay(Bevel(raised: true, width: 3))
                        .overlay(Rectangle().stroke(Retro.ink, lineWidth: 1.5))
                }
            }
        }
        .textCase(.uppercase)
        .foregroundStyle(Retro.ink)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusTag: some View {
        switch state {
        case .idle:
            EmptyView()
        case .working:
            tag {
                ProgressView().controlSize(.mini).tint(Retro.lavender)
                Text("Dressing you…")
            }
        case .ready:
            tag {
                Text(showOriginal ? "Original · tap" : "\(serviceLabel) · tap")
            }
        case .failed(let message):
            Button(action: onRetry) {
                tag { Text("Failed · retry") }
            }
            .accessibilityHint(message)
        }
    }

    private func tag<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6, content: content)
            .font(Retro.font(11, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(Retro.lavender)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Retro.navy)
            .overlay(Rectangle().stroke(Retro.lavender, lineWidth: 1))
    }

    private var stamps: some View {
        let progress = min(abs(offset.width) / 120, 1)
        return ZStack {
            stamp("Dress me", color: Retro.electricBlue, angle: -12)
                .opacity(offset.width > 0 ? progress : 0)
            stamp("As if!", color: .red, angle: 12)
                .opacity(offset.width < 0 ? progress : 0)
        }
    }

    private func stamp(_ text: String, color: Color, angle: Double) -> some View {
        Text(text)
            .font(Retro.font(32))
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(Retro.lavender.opacity(0.85))
            .overlay(Rectangle().stroke(color, lineWidth: 4))
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
                        Retro.periwinkle
                        ProgressView().tint(Retro.navy)
                    }
                }
            }
        } else {
            GarmentArtView(category: product.category, hex: product.swatchHex)
        }
    }
}
