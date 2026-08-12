@preconcurrency import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private let model = ShareCaptureModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 243 / 255, green: 240 / 255, blue: 231 / 255, alpha: 1)

        let host = UIHostingController(
            rootView: ShareCaptureView(
                model: model,
                onCancel: { [weak self] in
                    self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
                },
                onSaved: { [weak self] in
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }
            )
        )
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        model.load(from: extensionContext)
    }
}

@MainActor
final class ShareCaptureModel: ObservableObject {
    @Published var kindRawValue = "note"
    @Published var title = ""
    @Published var thought = ""
    @Published var sourceURLString: String?
    @Published var originalFilename: String?
    @Published var payload: Data?
    @Published var selectedIdea = ""
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var itemCount = 0

    private(set) var drafts: [LoadedShare] = []

    var photoPayloads: [Data] {
        drafts.filter { $0.kindRawValue == "photo" }.compactMap(\.payload)
    }

    let ideaTitles = MaybeSharedContainer.publishedIdeaTitles

    func load(from context: NSExtensionContext?) {
        guard let extensionItem = context?.inputItems.first as? NSExtensionItem,
              let providers = extensionItem.attachments,
              !providers.isEmpty else {
            isLoading = false
            return
        }

        Task {
            var loaded: [LoadedShare] = []
            for provider in providers {
                if let draft = await load(provider) {
                    loaded.append(draft)
                }
            }
            drafts = loaded
            let photoCount = loaded.filter { $0.kindRawValue == "photo" }.count
            // Several photos shared together become one Maybe, so count what
            // will actually be saved.
            itemCount = photoCount > 0 ? loaded.count - photoCount + 1 : loaded.count
            if let first = loaded.first {
                kindRawValue = first.kindRawValue
                title = first.title
                sourceURLString = first.sourceURLString
                originalFilename = first.originalFilename
                payload = first.payload
            }
            if loaded.isEmpty, errorMessage == nil {
                errorMessage = "Maybe couldn’t read these shared items."
            }
            isLoading = false
        }
    }

    private func load(_ provider: NSItemProvider) async -> LoadedShare? {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let name = provider.suggestedName ?? "Photo"
            return await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(for: .image) { data, error in
                    continuation.resume(returning: data.map {
                        LoadedShare(
                            kindRawValue: "photo",
                            title: name,
                            originalFilename: provider.suggestedName.map { "\($0).jpg" } ?? "shared-photo.jpg",
                            payload: $0
                        )
                    })
                    if let error {
                        Task { @MainActor [weak self] in self?.errorMessage = error.localizedDescription }
                    }
                }
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, error in
                    let urlString = (value as? URL)?.absoluteString ?? (value as? String)
                    continuation.resume(returning: urlString.map {
                        LoadedShare(
                            kindRawValue: "link",
                            title: URL(string: $0)?.host() ?? "Link",
                            sourceURLString: $0
                        )
                    })
                    if let error {
                        Task { @MainActor [weak self] in self?.errorMessage = error.localizedDescription }
                    }
                }
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { value, error in
                    let fileURL = value as? URL
                    let data = fileURL.flatMap { try? Data(contentsOf: $0) }
                    let filename = fileURL?.lastPathComponent
                    continuation.resume(returning: data.map {
                        LoadedShare(
                            kindRawValue: "file",
                            title: filename ?? "File",
                            originalFilename: filename,
                            payload: $0
                        )
                    })
                    if let error {
                        Task { @MainActor [weak self] in self?.errorMessage = error.localizedDescription }
                    }
                }
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            return await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { value, error in
                    let sharedText = (value as? String) ?? ""
                    continuation.resume(returning: LoadedShare(
                        kindRawValue: "note",
                        title: sharedText.isEmpty ? "Note" : sharedText
                    ))
                    if let error {
                        Task { @MainActor [weak self] in self?.errorMessage = error.localizedDescription }
                    }
                }
            }
        }

        return nil
    }

    func save() throws {
        guard !drafts.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedThought = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        let idea = selectedIdea.isEmpty ? nil : selectedIdea

        let photos = drafts.filter { $0.kindRawValue == "photo" }
        let rest = drafts.filter { $0.kindRawValue != "photo" }

        if !photos.isEmpty {
            let fallback = photos.count > 1 ? "\(photos.count) photos" : (photos[0].title)
            let record = SharedCaptureRecord(
                kindRawValue: "photo",
                title: normalizedTitle.isEmpty ? fallback : normalizedTitle,
                thought: normalizedThought,
                ideaTitle: idea
            )
            try MaybeSharedContainer.enqueue(record, payloads: photos.compactMap(\.payload))
        }

        for draft in rest {
            let record = SharedCaptureRecord(
                kindRawValue: draft.kindRawValue,
                title: draft.title,
                thought: normalizedThought,
                sourceURLString: draft.sourceURLString,
                originalFilename: draft.originalFilename,
                ideaTitle: idea
            )
            try MaybeSharedContainer.enqueue(record, payloads: draft.payload.map { [$0] } ?? [])
        }
    }
}

struct LoadedShare: Sendable {
    let kindRawValue: String
    let title: String
    var sourceURLString: String? = nil
    var originalFilename: String? = nil
    var payload: Data? = nil
}

private struct ShareCaptureView: View {
    @ObservedObject var model: ShareCaptureModel
    let onCancel: () -> Void
    let onSaved: () -> Void

    var body: some View {
        ZStack {
            CreamCanvas()

            VStack(spacing: 20) {
                HStack {
                    Button("Cancel", action: onCancel)
                        .font(.maybeControl)
                        .foregroundStyle(MaybePalette.ink)
                    Spacer()
                    Text(model.itemCount > 1 ? "Add \(model.itemCount) things" : "Add to Maybe")
                        .font(.maybeRounded(17, weight: .black))
                        .foregroundStyle(MaybePalette.ink)
                    Spacer()
                    Color.clear.frame(width: 56, height: 1)
                }

                if model.isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else {
                    preview

                    VStack(alignment: .leading, spacing: 9) {
                        Text("What caught you?")
                            .font(.maybeSectionTitle)
                            .foregroundStyle(MaybePalette.ink)
                        TextField("Add a thought…", text: $model.thought, axis: .vertical)
                            .lineLimit(2...5)
                            .font(.system(size: 16))
                            .padding(15)
                            .maybePanel(cornerRadius: 18)
                    }

                    if !model.ideaTitles.isEmpty {
                        Picker("Add to idea", selection: $model.selectedIdea) {
                            Text("Inbox only").tag("")
                            ForEach(model.ideaTitles, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .tint(MaybePalette.ink)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        .padding(.horizontal, 14)
                        .maybePanel(cornerRadius: 18)
                    }

                    Spacer(minLength: 0)

                    Button {
                        do {
                            try model.save()
                            MaybeHaptics.saved()
                            onSaved()
                        } catch {
                            model.errorMessage = error.localizedDescription
                        }
                    } label: {
                        Text("Save")
                    }
                    .buttonStyle(KeycapButtonStyle(color: MaybePalette.yellow, cornerRadius: 20, minHeight: 54))
                }
            }
            .padding(20)
        }
        .alert("Couldn’t save", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "Please try again.")
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            let photos = model.photoPayloads
            if photos.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: previewSymbol)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MaybePalette.ink)
                        .frame(width: 62, height: 60)
                        .background { KeycapSurface(color: previewColor, cornerRadius: 18, depth: 2) }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.title.isEmpty ? model.kindRawValue.capitalized : model.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(MaybePalette.ink)
                            .lineLimit(2)
                        Text(model.kindRawValue.capitalized)
                            .font(.maybeMeta)
                            .foregroundStyle(MaybePalette.inkSoft)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(photos.prefix(6).enumerated()), id: \.offset) { _, data in
                            if let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 84, height: 100)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(MaybePalette.hairline, lineWidth: 1)
                                    }
                            }
                        }
                    }
                }
                Text(photos.count > 1 ? "\(photos.count) photos, saved as one Maybe" : "1 photo")
                    .font(.maybeMeta)
                    .foregroundStyle(MaybePalette.inkSoft)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .maybePanel(cornerRadius: 22)
    }

    private var previewSymbol: String {
        switch model.kindRawValue {
        case "photo": "photo.fill"
        case "link": "link"
        case "file": "doc.fill"
        default: "text.quote"
        }
    }

    private var previewColor: Color {
        switch model.kindRawValue {
        case "photo": MaybePalette.blue
        case "link": MaybePalette.green
        case "file": MaybePalette.purple
        default: MaybePalette.yellow
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}
