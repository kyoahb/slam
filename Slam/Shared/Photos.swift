import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers
import SlamCore

/// Adding photos and videos: camera or library. One per workout screen, shown from a button or the strip.
struct MediaAdder: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var photos: [Photo]
    @Binding var choosing: Bool
    @State private var library = false
    @State private var camera = false
    @State private var items: [PhotosPickerItem] = []
    @State private var importing = 0

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Add a photo or video", isPresented: $choosing) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Camera") { camera = true }
                }
                Button("Choose from Library") { library = true }
            }
            .photosPicker(isPresented: $library, selection: $items, maxSelectionCount: 10, matching: .any(of: [.images, .videos]))
            .fullScreenCover(isPresented: $camera) {
                CameraView(onImage: { add(model.addPhoto($0)) },
                           onVideo: { url in importing += 1; Task { add(await model.addVideo(url)); importing -= 1 } },
                           onClose: { camera = false })
                    .ignoresSafeArea()
            }
            .onChange(of: items) { _, picked in
                guard !picked.isEmpty else { return }
                items = []
                importing += picked.count
                Task {
                    for item in picked {
                        add(await load(item))
                        importing -= 1
                    }
                }
            }
            .overlay(alignment: .top) {
                if importing > 0 {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Adding").font(.footnote)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Theme.control))
                    .padding(.top, 8)
                }
            }
    }

    private func load(_ item: PhotosPickerItem) async -> Photo? {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else { return nil }
            defer { try? FileManager.default.removeItem(at: movie.url) }
            return await model.addVideo(movie.url)
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return model.addPhoto(data)
    }

    private func add(_ p: Photo?) {
        if let p { photos.append(p) }
    }
}

extension View {
    func mediaAdder(_ photos: Binding<[Photo]>, choosing: Binding<Bool>) -> some View {
        modifier(MediaAdder(photos: photos, choosing: choosing))
    }
}

/// A video from the library, copied somewhere the app may read it.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "." + (received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension))
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// Add a photo or video; each keeps the time it was attached.
struct PhotoStrip: View {
    @Environment(AppModel.self) private var model
    @Binding var photos: [Photo]
    @State private var choosing = false
    @State private var viewing: Photo?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button { choosing = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "camera").font(.title2)
                        Text("Add photo or video").font(.footnote).multilineTextAlignment(.center)
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
                        Button(p.isVideo ? "Remove Video" : "Remove Photo", systemImage: "trash", role: .destructive) {
                            photos.removeAll { $0.id == p.id }
                        }
                    }
                }
            }
        }
        .mediaAdder($photos, choosing: $choosing)
        .fullScreenCover(item: $viewing) { p in
            PhotoViewer(photo: p).environment(model)
        }
    }
}

/// A photo, or a video's first frame with a play mark.
struct StoredImage: View {
    @Environment(AppModel.self) private var model
    let file: String
    var full = false

    var body: some View {
        Group {
            if let image = full ? model.image(file) : model.thumbnail(file) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: full ? .fit : .fill)
            } else {
                Rectangle().fill(Theme.surface)
            }
        }
        .overlay {
            if Photo.isVideo(file) && !full {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.black.opacity(0.55)))
            }
        }
    }
}

struct PhotoViewer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let photo: Photo
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if photo.isVideo {
                if let player {
                    VideoPlayer(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "icloud.and.arrow.down").font(.title)
                        Text("This video is still on the server").font(.footnote)
                    }
                    .foregroundStyle(Theme.grey)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                StoredImage(file: photo.file, full: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
                    .padding(.bottom, photo.isVideo ? 60 : 0)
            }
            .padding(16)
        }
        .onAppear {
            guard photo.isVideo, let url = model.mediaURL(photo.file) else { return }
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear { player?.pause() }
    }
}

/// The system camera, for a photo or a video.
struct CameraView: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    var onVideo: (URL) -> Void = { _ in }
    let onClose: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeHigh
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
            if let url = info[.mediaURL] as? URL {
                // The camera's file goes away once this returns.
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                if (try? FileManager.default.copyItem(at: url, to: copy)) != nil { parent.onVideo(copy) }
            } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                parent.onImage(data)
            }
            parent.onClose()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onClose()
        }
    }
}
