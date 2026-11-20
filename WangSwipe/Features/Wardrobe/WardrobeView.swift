import SwiftUI

/// The main screen, laid out like a 90s wardrobe computer: two display panels
/// (upper and lower garment) with back / play / forward controls, Shuffle and
/// Dress Me buttons, leopard print around it, and a menu strip of sections.
struct WardrobeView: View {
    @Environment(AppModel.self) private var appModel
    @State private var mirrorOutfit: [Product]?

    private var wardrobe: WardrobeModel { appModel.wardrobe }

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(title: Skin.current.wardrobeTitle)
                .contentShape(Rectangle())
                .onTapGesture { appModel.updateSettings { $0.skin = $0.skin.next } }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Switches to the next skin")

            ZStack {
                SkinBackdrop()

                VStack(spacing: 10) {
                    panel(.upper)
                    panel(.lower)
                    bigButtons
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 12)

                if let outfit = mirrorOutfit {
                    Color.black.opacity(0.35)
                        .onTapGesture { withAnimation { mirrorOutfit = nil } }
                        .transition(.opacity)
                    MirrorView(
                        outfit: outfit,
                        state: appModel.dresser.state(for: outfit),
                        person: appModel.userPhoto,
                        serviceLabel: appModel.dresser.serviceLabel,
                        onBack: { withAnimation { mirrorOutfit = nil } },
                        onKeep: {
                            outfit.forEach(appModel.like)
                            withAnimation { mirrorOutfit = nil }
                        },
                        onRetry: { appModel.dresser.dress(outfit) }
                    )
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .transition(.opacity)
                }
            }

            SectionStrip(
                available: Set(wardrobe.availableSections),
                selected: wardrobe.section,
                onSelect: { section in withAnimation(.snappy) { wardrobe.select(section) } }
            )
        }
        .overlay(Scanlines())
        .task { await wardrobe.load() }
        .onDisappear { wardrobe.stop() }
    }

    private func panel(_ slot: OutfitSlot) -> some View {
        GarmentPanel(
            product: wardrobe.current(slot),
            isLoading: wardrobe.isLoading,
            isPlaying: wardrobe.isPlaying,
            onBack: { withAnimation(.snappy) { wardrobe.skip(slot, by: -1) } },
            onPlay: { wardrobe.togglePlay() },
            onForward: { withAnimation(.snappy) { wardrobe.skip(slot, by: 1) } }
        )
    }

    private var bigButtons: some View {
        HStack(spacing: 14) {
            Button {
                withAnimation(.snappy) { wardrobe.shuffle() }
            } label: {
                Text("Shuffle")
            }
            .buttonStyle(.bevelPrimary)

            Button {
                wardrobe.stop()
                let outfit = wardrobe.outfit
                guard !outfit.isEmpty else { return }
                appModel.dresser.dress(outfit)
                withAnimation { mirrorOutfit = outfit }
            } label: {
                Text("Dress Me")
            }
            .buttonStyle(BevelButtonStyle(size: 22))
        }
        .frame(height: 60)
        .disabled(wardrobe.outfit.isEmpty)
    }
}

/// One display window with its own back / play / forward controls.
/// Swiping the picture left or right also skips.
struct GarmentPanel: View {
    let product: Product?
    let isLoading: Bool
    let isPlaying: Bool
    var onBack: () -> Void
    var onPlay: () -> Void
    var onForward: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Retro.panel
                .overlay {
                    if let product {
                        ProductImageView(product: product, fill: false)
                            .padding(8)
                            .id(product.id)
                            .transition(.opacity)
                    } else if isLoading {
                        ProgressView().tint(Retro.ink)
                    } else {
                        Text("Nothing here").font(Retro.font(14)).foregroundStyle(Retro.ink)
                    }
                }
                .overlay(alignment: .bottomLeading) { caption }
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 20).onEnded { value in
                        if value.translation.width < -40 { onForward() }
                        if value.translation.width > 40 { onBack() }
                    }
                )
                .overlay(Bevel(raised: false, width: 4))

            HStack(spacing: 6) {
                control("backward.fill", action: onBack)
                control(isPlaying ? "pause.fill" : "play.fill", action: onPlay)
                control("forward.fill", action: onForward)
            }
            .padding(6)
            .frame(height: 52)
            .background(Retro.panelAlt)
        }
        .overlay(Rectangle().stroke(Retro.ink, lineWidth: 2))
    }

    @ViewBuilder
    private var caption: some View {
        if let product {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(product.brand ?? product.storeName) · \(product.storeName)")
                        .font(Retro.font(9, weight: .bold))
                        .opacity(0.8)
                    Text(product.title)
                        .font(Retro.font(11))
                        .lineLimit(1)
                    Text(product.formattedPrice)
                        .font(Retro.font(10, weight: .bold))
                }
                if let url = product.productURL {
                    Link(destination: url) {
                        Image(systemName: "bag.fill").font(.system(size: 12, weight: .bold))
                    }
                }
            }
            .textCase(.uppercase)
            .foregroundStyle(Retro.onBar)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Retro.bar.opacity(0.85))
            .padding(6)
        }
    }

    private func control(_ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .black))
        }
        .buttonStyle(BevelButtonStyle(size: 16))
    }
}

/// Bottom menu strip of menswear sections, with MORE on the right to show everything.
/// Sections with nothing in them right now are dimmed.
struct SectionStrip: View {
    let available: Set<MensSection>
    let selected: MensSection?
    var onSelect: (MensSection?) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MensSection.allCases) { section in
                item(section.title, isOn: selected == section) { onSelect(section) }
                    .disabled(!available.contains(section))
                    .opacity(available.contains(section) ? 1 : 0.4)
            }
            Spacer(minLength: 2)
            Button { onSelect(nil) } label: {
                Text("More")
                    .font(Retro.font(12, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(selected == nil ? Retro.bar : Retro.onBar)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                    .background(selected == nil ? Retro.onBar : .clear)
                    .overlay(Rectangle().stroke(Retro.onBar, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Retro.bar)
    }

    private func item(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Retro.font(12, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(isOn ? Retro.bar : Retro.onBar)
                .padding(.horizontal, 4)
                .padding(.vertical, 5)
                .background(isOn ? Retro.onBar : .clear)
        }
        .buttonStyle(.plain)
    }
}
