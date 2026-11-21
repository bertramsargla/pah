import PhotosUI
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var apiKeyDraft = ""
    @State private var keySaved = false
    @State private var geminiKeyDraft = ""
    @State private var geminiKeySaved = false
    @State private var sensoKeyDraft = ""
    @State private var sensoKeySaved = false
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
                geminiKeyDraft = appModel.geminiAPIKey
                sensoKeyDraft = appModel.sensoAPIKey
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
            SecureField("Gemini API key", text: $geminiKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(geminiKeySaved ? "Saved" : "Save key") {
                appModel.setGeminiAPIKey(geminiKeyDraft)
                geminiKeySaved = true
            }
            .disabled(geminiKeyDraft.isEmpty)
            .onChange(of: geminiKeyDraft) { geminiKeySaved = false }

            SecureField("Senso API key (optional)", text: $sensoKeyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(sensoKeySaved ? "Saved" : "Save Senso key") {
                appModel.setSensoAPIKey(sensoKeyDraft)
                sensoKeySaved = true
            }
            .disabled(sensoKeyDraft.isEmpty)
            .onChange(of: sensoKeyDraft) { sensoKeySaved = false }
            if let status = appModel.sensoStatus {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Agent")
        } footer: {
            Text("""
            The Agent tab uses Google Gemini (\(GeminiStylist.model), \(GeminiStylist.thinkingLevel) thinking) and charges your Google account per message, \
            roughly a few cents per reply. Your photo, latest try-on and the wardrobe are sent with the chat. \
            With a Senso key, the app files a style guide and the wardrobe in your Senso knowledge base, \
            and each question first searches it for notes to pass to Gemini (uses Senso credits). \
            Keys are kept in this phone's Keychain.
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
