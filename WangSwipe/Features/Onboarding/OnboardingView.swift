import PhotosUI
import SwiftUI

/// First screen: the user adds a full-body photo that every try-on uses.
struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @State private var pickerItem: PhotosPickerItem?
    @State private var selected: UIImage?
    @State private var showingCamera = false
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("WangSwipe")
                    .font(.largeTitle.bold())
                Text("Add a photo of yourself, then swipe through clothes from different stores, already on you.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)

            photoPreview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Label("Full body, standing, facing the camera", systemImage: "figure.stand")
                Label("Plain background and good light", systemImage: "sun.max")
                Label("Fitted clothes work best", systemImage: "tshirt")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            if let loadError {
                Text(loadError).font(.footnote).foregroundStyle(.red)
            }

            VStack(spacing: 12) {
                if let selected {
                    Button {
                        appModel.setPhoto(selected)
                    } label: {
                        Text("Start swiping").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                HStack(spacing: 12) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(selected == nil ? "Choose photo" : "Choose another", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if CameraPicker.isAvailable {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take photo", systemImage: "camera").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .controlSize(.large)
            }

            Text("Your photo stays on this phone. It's only sent to a try-on service if you turn one on in Settings.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
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
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.quaternary)
                .overlay {
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                loadError = "Couldn't open that photo. Try another one."
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
