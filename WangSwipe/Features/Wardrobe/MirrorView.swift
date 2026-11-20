import SwiftUI

/// Shows the result of Dress Me: the user's photo while the outfit is being
/// put on (upper garment, then lower), then the finished look.
struct MirrorView: View {
    let outfit: [Product]
    let state: Dresser.State
    let person: UIImage?
    let serviceLabel: String
    var onBack: () -> Void
    var onKeep: () -> Void
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(left: outfit.map { $0.brand ?? $0.storeName }.joined(separator: " + "), title: "Mirror")

            Retro.panelAlt
                .overlay { picture }
                .overlay(alignment: .top) { status.padding(10) }
                .clipped()
                .overlay(Bevel(raised: false, width: 4))

            HStack(spacing: 12) {
                Button("Back", action: onBack)
                    .buttonStyle(BevelButtonStyle(size: 20))
                if case .ready = state {
                    Button("Keep", action: onKeep)
                        .buttonStyle(.bevelPrimary)
                } else if case .failed = state {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.bevelPrimary)
                }
            }
            .frame(height: 58)
            .padding(10)
            .background(Retro.panel)
        }
        .overlay(Rectangle().stroke(Retro.ink, lineWidth: 2))
        .background(Rectangle().fill(.black.opacity(0.35)).offset(x: 5, y: 5))
    }

    @ViewBuilder
    private var picture: some View {
        if case .ready(let image) = state {
            Image(uiImage: image).resizable().scaledToFit()
        } else if let person {
            Image(uiImage: person).resizable().scaledToFit()
                .opacity(0.55)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .idle:
            EmptyView()
        case .working(let step, let total, let item):
            tag {
                ProgressView().controlSize(.mini).tint(Retro.onBar)
                Text("Dressing you \(step)/\(total): \(item)")
            }
        case .ready:
            tag { Text(serviceLabel) }
        case .failed(let message):
            VStack(spacing: 4) {
                tag { Text("Couldn't dress you") }
                Text(message)
                    .font(Retro.font(10, weight: .medium))
                    .foregroundStyle(Retro.onBar)
                    .lineLimit(4)
                    .padding(6)
                    .background(Retro.bar.opacity(0.85))
            }
        }
    }

    private func tag<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6, content: content)
            .font(Retro.font(11, weight: .bold))
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(Retro.onBar)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Retro.bar)
            .overlay(Rectangle().stroke(Retro.onBar, lineWidth: 1))
    }
}
