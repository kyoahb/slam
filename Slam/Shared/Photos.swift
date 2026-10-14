import SwiftUI
import PhotosUI
import SlamCore

/// Add a photo (camera or library); each keeps the time it was attached.
struct PhotoStrip: View {
    @Environment(AppModel.self) private var model
    @Binding var photos: [Photo]
    @State private var choosing = false
    @State private var library = false
    @State private var camera = false
    @State private var item: PhotosPickerItem?
    @State private var viewing: Photo?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button { choosing = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "camera").font(.title2)
                        Text("Add a photo").font(.footnote)
                    }
                    .foregroundStyle(Theme.grey)
                    .frame(width: 104, height: 104)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.grey, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                }
                .buttonStyle(.plain)
                ForEach(photos) { p in
                    Button { viewing = p } label: {
                        StoredImage(file: p.file)
                            .frame(width: 104, height: 104)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .bottomLeading) {
                                Text(p.addedAt.time)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.black.opacity(0.6)))
                                    .padding(5)
                            }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove Photo", systemImage: "trash", role: .destructive) {
                            photos.removeAll { $0.id == p.id }
                        }
                    }
                }
            }
        }
        .confirmationDialog("Add a photo", isPresented: $choosing) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") { camera = true }
            }
            Button("Choose from Library") { library = true }
        }
        .photosPicker(isPresented: $library, selection: $item, matching: .images)
        .fullScreenCover(isPresented: $camera) {
            CameraView(onImage: { add($0) }, onClose: { camera = false }).ignoresSafeArea()
        }
        .fullScreenCover(item: $viewing) { p in
            PhotoViewer(photo: p).environment(model)
        }
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task {
                if let data = try? await picked.loadTransferable(type: Data.self) { add(data) }
                item = nil
            }
        }
    }

    private func add(_ data: Data) {
        if let p = model.addPhoto(data) { photos.append(p) }
    }
}

struct StoredImage: View {
    @Environment(AppModel.self) private var model
    let file: String
    var full = false

    var body: some View {
        if let image = full ? model.image(file) : model.thumbnail(file) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: full ? .fit : .fill)
        } else {
            Rectangle().fill(Theme.surface)
        }
    }
}

struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let photo: Photo

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            StoredImage(file: photo.file, full: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .trailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Theme.control))
                }
                .buttonStyle(.plain)
                Spacer()
                Text(photo.addedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(Theme.grey)
            }
            .padding(16)
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                parent.onImage(data)
            }
            parent.onClose()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onClose()
        }
    }
}
