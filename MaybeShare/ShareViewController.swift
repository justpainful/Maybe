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
    @Published var title = "Shared with Maybe"
    @Published var thought = ""
    @Published var sourceURLString: String?
    @Published var originalFilename: String?
    @Published var payload: Data?
    @Published var selectedIdea = ""
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var itemCount = 0

    private var drafts: [LoadedShare] = []

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
            itemCount = loaded.count
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
            let name = provider.suggestedName ?? "A photo that caught me"
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
                            title: URL(string: $0)?.host() ?? "A link worth keeping",
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
                            title: filename ?? "A saved file",
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
                        title: sharedText.isEmpty ? "A thought" : sharedText
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
        for (index, draft) in drafts.enumerated() {
            let record = SharedCaptureRecord(
                kindRawValue: draft.kindRawValue,
                title: index == 0 && !normalizedTitle.isEmpty ? normalizedTitle : draft.title,
                thought: normalizedThought,
                sourceURLString: draft.sourceURLString,
                originalFilename: draft.originalFilename,
                ideaTitle: selectedIdea.isEmpty ? nil : selectedIdea
            )
            try MaybeSharedContainer.enqueue(record, payload: draft.payload)
        }
    }
}

private struct LoadedShare: Sendable {
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
            Color(red: 243 / 255, green: 240 / 255, blue: 231 / 255)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                HStack {
                    Button("Cancel", action: onCancel)
                    Spacer()
                    Text(model.itemCount > 1 ? "Add \(model.itemCount) to Maybe" : "Add to Maybe")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Spacer()
                    Color.clear.frame(width: 52, height: 1)
                }

                if model.isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity)
                } else {
                    preview

                    VStack(alignment: .leading, spacing: 9) {
                        Text("What caught you?")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        TextField("Add a thought…", text: $model.thought, axis: .vertical)
                            .lineLimit(2...5)
                            .padding(15)
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    if !model.ideaTitles.isEmpty {
                        Picker("Add to idea", selection: $model.selectedIdea) {
                            Text("Inbox only").tag("")
                            ForEach(model.ideaTitles, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .padding(14)
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }

                    Spacer(minLength: 0)

                    Button {
                        do {
                            try model.save()
                            onSaved()
                        } catch {
                            model.errorMessage = error.localizedDescription
                        }
                    } label: {
                        Label("Save", systemImage: "arrow.down.to.line.compact")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(Color(red: 23 / 255, green: 23 / 255, blue: 23 / 255))
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color(red: 1, green: 216 / 255, blue: 61 / 255))
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
        HStack(spacing: 14) {
            Group {
                if model.kindRawValue == "photo", let data = model.payload, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: previewSymbol)
                        .font(.system(size: 27, weight: .bold))
                        .background(previewColor)
                }
            }
            .frame(width: 62, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .lineLimit(2)
                Text(model.kindRawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.itemCount > 1 {
                    Text("+ \(model.itemCount - 1) more")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(15)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
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
        case "photo": Color(red: 112 / 255, green: 174 / 255, blue: 1)
        case "link": Color(red: 135 / 255, green: 229 / 255, blue: 109 / 255)
        case "file": Color(red: 121 / 255, green: 87 / 255, blue: 1)
        default: Color(red: 1, green: 216 / 255, blue: 61 / 255)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}
