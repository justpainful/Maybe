import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct AddMaybeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedItem.modifiedAt, order: .reverse) private var existingItems: [SavedItem]

    @State private var kind: MaybeKind = .photo
    @State private var title = ""
    @State private var thought = ""
    @State private var sourceURL = ""
    @State private var tags = ""
    @State private var photoSelection: PhotosPickerItem?
    @State private var payload: Data?
    @State private var payloadFilename: String?
    @State private var isChoosingFile = false
    @State private var isSaving = false
    @State private var duplicateTitle: String?
    @State private var errorMessage: String?

    private let mediaStore = LocalMediaStore()
    private var recentTags: [String] {
        var seen = Set<String>()
        return existingItems
            .flatMap(\.tagNames)
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CreamCanvas()
                VStack(spacing: 0) {
                    composerHeader

                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            typePicker
                            contentInput
                            thoughtInput
                            tagsInput
                        }
                        .padding(.horizontal, MaybeMetrics.pageInset)
                        .padding(.top, 8)
                        .padding(.bottom, 18)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: save) {
                    HStack(spacing: 9) {
                        if isSaving {
                            ProgressView().tint(MaybePalette.ink)
                        } else {
                            Image(systemName: "tray.and.arrow.down.fill")
                        }
                        Text(isSaving ? "Saving…" : "Save to Inbox")
                    }
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.roundedRectangle(radius: 18))
                .tint(MaybePalette.yellow)
                .foregroundStyle(MaybePalette.ink)
                .disabled(isSaving)
                .accessibilityIdentifier("save-maybe-button")
                .padding(.horizontal, MaybeMetrics.pageInset)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(MaybePalette.cream.opacity(0.82))
            }
            .fileImporter(
                isPresented: $isChoosingFile,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false,
                onCompletion: importFile
            )
            .onChange(of: photoSelection) { _, newValue in
                guard let newValue else { return }
                Task {
                    do {
                        payload = try await newValue.loadTransferable(type: Data.self)
                        payloadFilename = "Maybe-photo.jpg"
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .alert("Already in Maybe", isPresented: duplicateAlertBinding) {
                Button("Open it later", role: .cancel) {}
            } message: {
                Text("This file is already saved as “\(duplicateTitle ?? "an existing Maybe")”.")
            }
            .alert("Couldn’t save", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private var composerHeader: some View {
        ZStack {
            Text("Add to Maybe")
                .font(.maybeRounded(20, weight: .bold))

            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MaybePalette.ink)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Close")

                Spacer()
            }
        }
        .frame(height: 48)
        .padding(.horizontal, MaybeMetrics.pageInset)
        .padding(.top, 4)
    }

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What are you keeping?")
                .font(.maybeRounded(20, weight: .bold))

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(MaybeKind.allCases) { option in
                        ComposerKindButton(
                            title: option.title,
                            symbol: composerSymbol(for: option),
                            color: accent(for: option),
                            isSelected: kind == option
                        ) {
                            withAnimation(.snappy(duration: 0.22)) {
                                kind = option
                            }
                        }
                        .accessibilityIdentifier("kind-\(option.rawValue)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var contentInput: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch kind {
            case .photo:
                let isReady = payload != nil
                PhotosPicker(selection: $photoSelection, matching: .images) {
                    MaybePickerSurface(
                        symbol: isReady ? "checkmark.circle.fill" : "photo.badge.plus",
                        title: isReady ? "Photo ready" : "Choose a photo",
                        subtitle: isReady ? "Tap to choose another" : "It stays on this device",
                        color: MaybePalette.blue
                    )
                }
                .buttonStyle(.plain)

            case .link:
                inputCard {
                    Label("Link", systemImage: "link")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    TextField("https://", text: $sourceURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

            case .note:
                inputCard {
                    Label("Your note", systemImage: "text.quote")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    TextField("A thought worth keeping…", text: $title, axis: .vertical)
                        .lineLimit(3...7)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                }

            case .file:
                Button {
                    isChoosingFile = true
                } label: {
                    MaybePickerSurface(
                        symbol: payload == nil ? "doc.badge.plus" : "checkmark.circle.fill",
                        title: payloadFilename ?? "Choose a file",
                        subtitle: payload == nil ? "A local copy goes into Maybe" : "Tap to choose another",
                        color: MaybePalette.purple
                    )
                }
                .buttonStyle(.plain)
            }

            if kind != .note {
                inputCard {
                    TextField("Give it a name (optional)", text: $title)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                }
            }
        }
    }

    private var thoughtInput: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Text("What caught you?")
                    .font(.maybeRounded(21, weight: .bold))
                Text("optional")
                    .font(.caption)
                    .foregroundStyle(MaybePalette.ink.opacity(0.45))
            }
            inputCard {
                TextField("The floating controls…", text: $thought, axis: .vertical)
                    .lineLimit(2...6)
            }
        }
    }

    private var tagsInput: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tags")
                .font(.maybeRounded(21, weight: .bold))
            inputCard {
                TextField("UI, Glass, Motion", text: $tags)
                    .textInputAutocapitalization(.words)
            }

            if !recentTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recentTags, id: \.self) { tag in
                            Button {
                                appendTag(tag)
                            } label: {
                                Text(tag)
                                    .font(.system(.caption, design: .rounded, weight: .bold))
                                    .foregroundStyle(MaybePalette.ink)
                                    .padding(.horizontal, 13)
                                    .frame(height: 34)
                                    .glassEffect(
                                        .regular.tint(MaybePalette.green.opacity(0.34)).interactive(),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(ComposerPressButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private func inputCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .maybeGlass(cornerRadius: 19)
    }

    private func accent(for kind: MaybeKind) -> Color {
        switch kind {
        case .photo: MaybePalette.blue
        case .link: MaybePalette.green
        case .note: MaybePalette.yellow
        case .file: MaybePalette.purple
        }
    }

    private func composerSymbol(for kind: MaybeKind) -> String {
        switch kind {
        case .photo: "photo.fill"
        case .link: "link"
        case .note: "text.quote"
        case .file: "doc.fill"
        }
    }

    private func appendTag(_ tag: String) {
        let existing = parsedTags.map { $0.lowercased() }
        guard !existing.contains(tag.lowercased()) else { return }
        tags = parsedTags.isEmpty ? tag : (parsedTags + [tag]).joined(separator: ", ")
    }

    private var duplicateAlertBinding: Binding<Bool> {
        Binding(
            get: { duplicateTitle != nil },
            set: { if !$0 { duplicateTitle = nil } }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            payload = try Data(contentsOf: url)
            payloadFilename = url.lastPathComponent
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }

        do {
            if let payload {
                let hash = LocalMediaStore.hash(payload)
                let attachments = try modelContext.fetch(FetchDescriptor<MediaAttachment>())
                if let duplicate = attachments.first(where: { $0.sha256 == hash }) {
                    duplicateTitle = duplicate.item?.title ?? duplicate.originalFilename
                    return
                }
            }

            let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackTitle: String
            switch kind {
            case .photo: fallbackTitle = "A photo that caught me"
            case .link: fallbackTitle = URL(string: sourceURL)?.host() ?? "A link worth keeping"
            case .note: fallbackTitle = thought.isEmpty ? "A thought" : thought
            case .file: fallbackTitle = payloadFilename ?? "A saved file"
            }

            let item = SavedItem(
                kind: kind,
                title: normalizedTitle.isEmpty ? fallbackTitle : normalizedTitle,
                note: thought.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceURLString: sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                isInbox: true,
                tagNames: parsedTags,
                accentHex: MaybePalette.accentHexes[existingItems.count % MaybePalette.accentHexes.count],
                visualSeed: existingItems.count % 5
            )
            modelContext.insert(item)

            if let payload {
                let mediaKind: MediaKind = kind == .photo ? .image : .file
                let filename = payloadFilename ?? "attachment"
                let path = try mediaStore.write(payload, filename: filename, kind: mediaKind)
                let image = UIImage(data: payload)
                let attachment = MediaAttachment(
                    type: mediaKind,
                    localPath: path,
                    thumbnailPath: mediaKind == .image ? try mediaStore.createThumbnail(from: payload) : nil,
                    width: image.map { Double($0.size.width) } ?? 0,
                    height: image.map { Double($0.size.height) } ?? 0,
                    originalFilename: filename,
                    sha256: LocalMediaStore.hash(payload),
                    item: item
                )
                item.media.append(attachment)
            }

            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var parsedTags: [String] {
        tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct ComposerKindButton: View {
    let title: String
    let symbol: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .frame(height: 22)

                Text(title)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(MaybePalette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .glassEffect(
                .regular
                    .tint(isSelected ? color.opacity(0.6) : Color.white.opacity(0.12))
                    .interactive(),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? MaybePalette.ink.opacity(0.14) : Color.white.opacity(0.36), lineWidth: 0.75)
            }
        }
        .buttonStyle(ComposerPressButtonStyle())
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

private struct ComposerPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 2 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.74), value: configuration.isPressed)
    }
}

private struct MaybePickerSurface: View {
    let symbol: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 21, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .frame(width: 46, height: 44)
                .glassEffect(
                    .regular.tint(color.opacity(0.52)),
                    in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(MaybePalette.ink.opacity(0.54))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MaybePalette.ink.opacity(0.48))
        }
        .foregroundStyle(MaybePalette.ink)
        .padding(13)
        .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .maybeGlass(cornerRadius: 21, tint: color.opacity(0.1), interactive: true)
    }
}

struct NewIdeaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedItem.createdAt, order: .reverse) private var items: [SavedItem]

    let preselectedItem: SavedItem?
    @State private var title = ""
    @State private var note = ""
    @State private var tags = ""
    @State private var selectedIDs: Set<UUID>
    @State private var coverItemID: UUID?
    @State private var errorMessage: String?

    init(preselectedItem: SavedItem?) {
        self.preselectedItem = preselectedItem
        _selectedIDs = State(initialValue: Set(preselectedItem.map { [$0.id] } ?? []))
        _coverItemID = State(initialValue: preselectedItem?.id)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CreamCanvas()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Name the idea")
                                .font(.maybeRounded(22, weight: .bold))
                            TextField("Maybe app UI", text: $title)
                                .font(.maybeRounded(26, weight: .bold))
                                .padding(17)
                                .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                                .maybeGlass(cornerRadius: 21)
                            TextField("What could this become?", text: $note, axis: .vertical)
                                .lineLimit(2...5)
                                .padding(17)
                                .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                                .maybeGlass(cornerRadius: 21)
                            TextField("Tags, separated by commas", text: $tags)
                                .padding(17)
                                .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                                .maybeGlass(cornerRadius: 21)
                        }

                        VStack(alignment: .leading, spacing: 11) {
                            Text("Inspired by")
                                .font(.maybeRounded(22, weight: .bold))
                            Text("Choose any things that helped shape it.")
                                .font(.subheadline)
                                .foregroundStyle(MaybePalette.ink.opacity(0.56))

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                                ForEach(items) { item in
                                    Button {
                                        if selectedIDs.contains(item.id) {
                                            selectedIDs.remove(item.id)
                                            if coverItemID == item.id { coverItemID = nil }
                                        } else {
                                            selectedIDs.insert(item.id)
                                            if coverItemID == nil { coverItemID = item.id }
                                        }
                                    } label: {
                                        InspirationThumbnail(item: item)
                                            .frame(height: 104)
                                            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                                            .overlay(alignment: .topTrailing) {
                                                if selectedIDs.contains(item.id) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .font(.title2)
                                                        .foregroundStyle(MaybePalette.ink, MaybePalette.green)
                                                        .padding(7)
                                                }
                                            }
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 19, style: .continuous)
                                                    .stroke(selectedIDs.contains(item.id) ? MaybePalette.ink : .clear, lineWidth: 2.5)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(item.title)
                                    .accessibilityValue(selectedIDs.contains(item.id) ? "Selected" : "Not selected")
                                }
                            }
                        }

                        if !selectedIDs.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Cover")
                                    .font(.maybeRounded(22, weight: .bold))
                                Picker("Cover Maybe", selection: $coverItemID) {
                                    Text("Automatic").tag(UUID?.none)
                                    ForEach(items.filter { selectedIDs.contains($0.id) }) { item in
                                        Text(item.title).tag(UUID?.some(item.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.horizontal, 14)
                                .background(Color.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .maybeGlass(cornerRadius: 18)
                            }
                        }

                        Button(action: save) {
                            Label("Create idea", systemImage: "lightbulb.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(KeycapButtonStyle(color: MaybePalette.green, cornerRadius: 22))
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("New idea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Couldn’t create the idea", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func save() {
        let selectedItems = items.filter { selectedIDs.contains($0.id) }
        let typedTags = tags.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let idea = Idea(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            coverItemID: coverItemID ?? selectedItems.first?.id,
            tagNames: Array(Set(typedTags + selectedItems.flatMap(\.tagNames))).sorted(),
            accentHex: MaybePalette.accentHexes[selectedIDs.count % MaybePalette.accentHexes.count],
            items: selectedItems
        )
        modelContext.insert(idea)
        selectedItems.forEach {
            $0.isInbox = false
            $0.modifiedAt = .now
        }
        do {
            try modelContext.save()
            let allIdeaTitles = (try modelContext.fetch(FetchDescriptor<Idea>())).map(\.title)
            MaybeSharedContainer.publishIdeaTitles(allIdeaTitles)
            dismiss()
        } catch {
            modelContext.delete(idea)
            errorMessage = error.localizedDescription
        }
    }
}

struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let item: SavedItem
    @State private var ideaSeed: SavedItem?
    @State private var isEditing = false
    @State private var isAddingToIdea = false
    @State private var previewAttachment: MediaAttachment?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Button {
                    previewAttachment = item.media.first
                } label: {
                    InspirationThumbnail(item: item, prefersOriginal: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: 420)
                        .clipped()
                }
                .buttonStyle(.plain)
                .disabled(item.media.isEmpty)

                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text(item.title)
                                .font(.maybeRounded(30, weight: .black))
                            Spacer()
                            Button {
                                item.isFavorite.toggle()
                                item.modifiedAt = .now
                                try? modelContext.save()
                            } label: {
                                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                                    .foregroundStyle(item.isFavorite ? MaybePalette.coral : MaybePalette.ink)
                            }
                            .buttonStyle(RoundKeycapButtonStyle(color: MaybePalette.glassWhite, size: 48))
                            .accessibilityLabel(item.isFavorite ? "Remove favorite" : "Favorite")
                        }

                        Label(item.kind.title, systemImage: item.kind.symbol)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(MaybePalette.ink.opacity(0.55))
                    }

                    if !item.note.isEmpty {
                        detailPanel(title: "Why I saved this", symbol: "sparkles") {
                            Text(item.note)
                                .font(.body)
                                .foregroundStyle(MaybePalette.ink)
                        }
                    }

                    if !item.tagNames.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tags")
                                .font(.maybeRounded(19, weight: .bold))
                            FlowTags(tags: item.tagNames, accent: Color(hex: item.accentHex))
                        }
                    }

                    if !item.ideas.isEmpty {
                        detailPanel(title: "Used in", symbol: "lightbulb.fill") {
                            ForEach(item.ideas) { idea in
                                NavigationLink {
                                    IdeaDetailView(idea: idea)
                                } label: {
                                    HStack {
                                        Text(idea.title)
                                            .font(.system(.headline, design: .rounded, weight: .bold))
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .foregroundStyle(MaybePalette.ink)
                                }
                            }
                        }
                    }

                    if let source = item.sourceURLString, !source.isEmpty {
                        detailPanel(title: "Source", symbol: "link") {
                            Link(destination: URL(string: source) ?? URL(string: "https://example.com")!) {
                                HStack {
                                    Text(URL(string: source)?.host() ?? source)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                }
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(MaybePalette.ink)
                            }
                        }
                    }

                    if let attachment = item.media.first {
                        detailPanel(title: "Local file", symbol: "internaldrive.fill") {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(attachment.originalFilename)
                                        .font(.system(.headline, design: .rounded, weight: .bold))
                                        .lineLimit(2)
                                    Text("Stored only on this device")
                                        .font(.caption)
                                        .foregroundStyle(MaybePalette.ink.opacity(0.56))
                                }
                                Spacer()
                                ShareLink(item: LocalMediaStore().url(at: attachment.localPath)) {
                                    Image(systemName: "square.and.arrow.up")
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.circle)
                                .accessibilityLabel("Share local file")
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        Button {
                            isAddingToIdea = true
                        } label: {
                            Label("Add to an idea", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 20))
                        .tint(MaybePalette.purple)
                        .foregroundStyle(MaybePalette.ink)

                        Button {
                            ideaSeed = item
                        } label: {
                            Label("Make a new idea from this", systemImage: "lightbulb.max.fill")
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.roundedRectangle(radius: 20))
                        .tint(MaybePalette.yellow.opacity(0.58))
                        .foregroundStyle(MaybePalette.ink)
                    }
                }
                .padding(20)
                .padding(.bottom, 30)
                .background(MaybePalette.cream)
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isEditing = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit Maybe")
            }
        }
        .task {
            item.lastViewedAt = .now
            try? modelContext.save()
        }
        .sheet(item: $ideaSeed) { seed in
            NewIdeaSheet(preselectedItem: seed)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isEditing) {
            EditItemSheet(item: item, onDeleted: { dismiss() })
                .presentationDetents([.large])
        }
        .sheet(isPresented: $isAddingToIdea) {
            AddToIdeaSheet(item: item)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $previewAttachment) { attachment in
            LocalMediaPreview(attachment: attachment, title: item.title)
        }
    }

    private func detailPanel<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.maybeRounded(19, weight: .bold))
            content()
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.44), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .maybeGlass(cornerRadius: 22)
    }
}

struct IdeaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let idea: Idea
    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 13)]
    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(idea.title)
                        .font(.maybeRounded(36, weight: .black))
                    Text(idea.note)
                        .font(.body)
                        .foregroundStyle(MaybePalette.ink.opacity(0.6))
                }

                HStack {
                    Label("Inspired by \(idea.items.count) things", systemImage: "sparkles.rectangle.stack.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    Spacer()
                }
                .padding(16)
                .background(Color(hex: idea.accentHex).opacity(0.46), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .maybeGlass(cornerRadius: 20, tint: Color(hex: idea.accentHex).opacity(0.2))

                LazyVGrid(columns: columns, spacing: 15) {
                    ForEach(idea.items) { item in
                        NavigationLink {
                            ItemDetailView(item: item)
                        } label: {
                            SavedCard(item: item, width: 168)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !idea.tagNames.isEmpty {
                    FlowTags(tags: idea.tagNames, accent: Color(hex: idea.accentHex))
                }
            }
            .padding(20)
            .padding(.bottom, 90)
        }
        .background(CreamCanvas())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isEditing = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit Idea")
            }
        }
        .sheet(isPresented: $isEditing) {
            EditIdeaSheet(idea: idea, onDeleted: { dismiss() })
                .presentationDetents([.large])
        }
    }
}

struct SurpriseView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [SavedItem]
    @State private var currentItem: SavedItem
    @State private var isAddingToIdea = false

    init(initialItem: SavedItem) {
        _currentItem = State(initialValue: initialItem)
    }

    var body: some View {
        ZStack {
            CreamCanvas()
            VStack(spacing: 20) {
                HStack {
                    Text("Maybe?")
                        .font(.maybeRounded(30, weight: .black))
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(RoundKeycapButtonStyle(color: MaybePalette.glassWhite, size: 46))
                    .accessibilityLabel("Close")
                }

                InspirationThumbnail(item: currentItem)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 500)
                    .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.white.opacity(0.86), lineWidth: 1.5))
                    .shadow(color: MaybePalette.ink.opacity(0.16), radius: 12, y: 8)

                VStack(alignment: .leading, spacing: 7) {
                    Text(currentItem.title)
                        .font(.maybeRounded(27, weight: .bold))
                    Text(currentItem.note)
                        .font(.body)
                        .foregroundStyle(MaybePalette.ink.opacity(0.62))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Button {
                        currentItem.isFavorite = true
                        currentItem.modifiedAt = .now
                        try? modelContext.save()
                    } label: {
                        Label("Keep around", systemImage: "heart.fill")
                    }
                    .buttonStyle(KeycapButtonStyle(color: MaybePalette.coral, cornerRadius: 20))

                    Button {
                        isAddingToIdea = true
                    } label: {
                        Label("Idea", systemImage: "lightbulb.fill")
                    }
                    .buttonStyle(KeycapButtonStyle(color: MaybePalette.green, cornerRadius: 20))

                    Button {
                        if let next = items.filter({ $0.id != currentItem.id }).randomElement() {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                currentItem = next
                            }
                        }
                    } label: {
                        Label("Next", systemImage: "arrow.right")
                    }
                    .buttonStyle(KeycapButtonStyle(color: MaybePalette.blue, cornerRadius: 20))
                }
            }
            .padding(20)
        }
        .task { viewed(currentItem) }
        .onChange(of: currentItem.id) { _, _ in viewed(currentItem) }
        .sheet(isPresented: $isAddingToIdea) {
            AddToIdeaSheet(item: currentItem)
                .presentationDetents([.medium, .large])
        }
    }

    private func viewed(_ item: SavedItem) {
        item.lastViewedAt = .now
        try? modelContext.save()
    }
}

private struct LocalMediaPreview: View {
    @Environment(\.dismiss) private var dismiss
    let attachment: MediaAttachment
    let title: String

    private let mediaStore = LocalMediaStore()

    var body: some View {
        NavigationStack {
            ZStack {
                MaybePalette.ink.ignoresSafeArea()
                if attachment.type == .image,
                   let image = UIImage(contentsOfFile: mediaStore.url(at: attachment.localPath).path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(title)
                } else {
                    ContentUnavailableView(
                        "Preview unavailable",
                        systemImage: "doc.fill",
                        description: Text(attachment.originalFilename)
                    )
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: mediaStore.url(at: attachment.localPath)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share file")
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
