import PhotosUI
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var apiKeyDraft = ""
    @State private var keySaved = false
    @State private var anthropicKeyDraft = ""
    @State private var anthropicKeySaved = false
    @State private var newDomain = ""

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(title: "Setup")
            Form {
                skinSection
                photoSection
                tryOnSection
                agentSection
                storesSection
            }
            .scrollContentBackground(.hidden)
            .background(Retro.panelAlt)
            .tint(Retro.tint)
            .onAppear {
                apiKeyDraft = appModel.falAPIKey
                anthropicKeyDraft = appModel.anthropicAPIKey
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        appModel.setPhoto(image)
                    }
                    pickerItem = nil
                }
            }
        }
    }

    // MARK: Sections

    private var skinSection: some View {
        Section {
            Picker("UI skin", selection: appModel.binding(\.skin)) {
                ForEach(Skin.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.menu)
        } header: {
            Text("Skin")
        } footer: {
            Text("The same dropdown opens from the box in the wardrobe's title bar.")
        }
    }

    private var photoSection: some View {
        Section("Your photo") {
            if let photo = appModel.userPhoto {
                HStack {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        PhotosPicker("Change photo", selection: $pickerItem, matching: .images)
                        Button("Remove photo", role: .destructive) { appModel.removePhoto() }
                    }
                }
            }
        }
    }

    private var tryOnSection: some View {
        Section {
            Picker("Engine", selection: appModel.binding(\.tryOnBackend)) {
                ForEach(TryOnBackend.allCases) { Text($0.displayName).tag($0) }
            }

            if appModel.settings.tryOnBackend == .fal {
                LabeledContent("Model", value: AppModel.tryOnModel.displayName)
                SecureField("fal.ai API key", text: $apiKeyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(keySaved ? "Saved" : "Save key") {
                    appModel.setFalAPIKey(apiKeyDraft)
                    keySaved = true
                }
                .disabled(apiKeyDraft.isEmpty)
                .onChange(of: apiKeyDraft) { keySaved = false }
            }
        } header: {
            Text("Virtual try-on")
        } footer: {
            Text("""
            Preview is free and runs on this phone, but it only lays the item over your photo. \
            fal.ai runs Google's Nano Banana, which dresses you in the whole outfit with one call \
            (about $0.04 per Dress Me), and your photo is sent to it. The key is kept in this phone's Keychain. For a public release, \
            make these calls from your own server instead.
            """)
        }
    }

    private var agentSection: some View {
        Section {
            SecureField("Anthropic API key", text: $anthropicKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(anthropicKeySaved ? "Saved" : "Save key") {
                appModel.setAnthropicAPIKey(anthropicKeyDraft)
                anthropicKeySaved = true
            }
            .disabled(anthropicKeyDraft.isEmpty)
            .onChange(of: anthropicKeyDraft) { anthropicKeySaved = false }
        } header: {
            Text("Agent")
        } footer: {
            Text("""
            The Agent tab uses Claude (\(ClaudeStylist.model)) and charges your Anthropic account per message, \
            roughly a few cents per reply. Your photo, latest try-on and the wardrobe are sent with the chat. \
            The key is kept in this phone's Keychain.
            """)
        }
    }

    private var storesSection: some View {
        Section {
            ForEach(CuratedStores.all, id: \.id) { store in
                Toggle(store.displayName, isOn: storeEnabled(store.id))
            }
            ForEach(appModel.settings.shopifyDomains, id: \.self) { domain in
                Toggle(domain, isOn: storeEnabled("shopify:\(domain)"))
                    .swipeActions {
                        Button("Remove", role: .destructive) {
                            appModel.updateSettings { $0.shopifyDomains.removeAll { $0 == domain } }
                        }
                    }
            }
            HStack {
                TextField("Add Shopify store domain", text: $newDomain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Add", action: addDomain)
                    .disabled(cleanedDomain.isEmpty)
            }
        } header: {
            Text("Stores")
        } footer: {
            Text("FWRD, Grailed and Farfetch are 10 hand-picked men's pieces. A Shopify store is read from its public product list, if the store allows it.")
        }
    }

    // MARK: Helpers

    private func storeEnabled(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !appModel.settings.disabledStoreIDs.contains(id) },
            set: { enabled in
                appModel.updateSettings {
                    if enabled { $0.disabledStoreIDs.remove(id) } else { $0.disabledStoreIDs.insert(id) }
                }
            }
        )
    }

    private var cleanedDomain: String {
        var value = newDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        return value.split(separator: "/").first.map(String.init) ?? ""
    }

    private func addDomain() {
        let domain = cleanedDomain
        guard !domain.isEmpty, !appModel.settings.shopifyDomains.contains(domain) else { return }
        appModel.updateSettings { $0.shopifyDomains.append(domain) }
        newDomain = ""
    }
}
