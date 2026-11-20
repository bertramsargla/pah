import PhotosUI
import SwiftUI

/// First screen: the user adds a full-body photo that every try-on uses.
/// Starts with the bundled demo photo selected, so a demo is one tap.
struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var selected: UIImage? = AppModel.demoPhoto
    @State private var showingCamera = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            RetroTitleBar(title: "New Client")

            ZStack {
                LeopardPattern()

                VStack(spacing: 14) {
                    RetroPanel {
                        VStack(spacing: 10) {
                            photoPreview
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            Text("Full body · facing camera · plain background")
                                .font(Retro.font(11, weight: .bold))
                                .textCase(.uppercase)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(Retro.ink)
                        }
                    }

                    if let loadError {
                        Text(loadError)
                            .font(Retro.font(12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.red)
                    }

                    HStack(spacing: 12) {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Library", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.bevel)

                        if CameraPicker.isAvailable {
                            Button {
                                showingCamera = true
                            } label: {
                                Label("Camera", systemImage: "camera")
                            }
                            .buttonStyle(.bevel)
                        }

                        Button {
                            selected = AppModel.demoPhoto
                        } label: {
                            Label("Demo", systemImage: "person.fill")
                        }
                        .buttonStyle(.bevel)
                    }
                    .frame(height: 50)

                    Button {
                        if let selected { appModel.setPhoto(selected) }
                    } label: {
                        Text("Dress Me")
                    }
                    .buttonStyle(.bevelPrimary)
                    .frame(height: 62)
                    .disabled(selected == nil)
                }
                .padding(20)
            }

            Text("Your photo stays on this phone unless you turn on AI try-on in Setup.")
                .font(Retro.font(10, weight: .medium))
                .textCase(.uppercase)
                .multilineTextAlignment(.center)
                .foregroundStyle(Retro.lavender)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(Retro.navy)
        }
        .overlay(Scanlines())
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in selected = image }
                .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let selected {
            Image(uiImage: selected)
                .resizable()
                .scaledToFit()
                .overlay(Rectangle().stroke(Retro.ink, lineWidth: 2))
        } else {
            Rectangle()
                .fill(Retro.periwinkle)
                .overlay {
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: 64))
                        .foregroundStyle(Retro.navy)
                }
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                loadError = "Couldn't open that photo"
                return
            }
            loadError = nil
            selected = image
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Wraps the system camera for taking a photo.
struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
