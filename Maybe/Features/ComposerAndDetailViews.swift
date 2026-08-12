import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Add

struct PhotoDraft: Identifiable {
    let id = UUID()
    let data: Data
    let preview: UIImage
    let aspect: CGFloat
}

enum ComposerField: Hashable {
    case note
    case link
    case thought
}

struct AddMaybeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedItem.modifiedAt, order: .reverse) private var existingItems: [SavedItem]

    @State private var kind: MaybeKind = .photo
    @State private var name = ""
    @State private var thought = ""
    @State private var sourceURL = ""
    @State private var selectedTags: [String] = []
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var photoDrafts: [PhotoDraft] = []
    @State private var filePayload: Data?
    @State private var fileName: String?
    @State private var isChoosingFile = false
    @State private var isChoosingPhotos = false
    @State private var isLoadingPhotos = false
    @State private var isSaving = false
    @State private var duplicateItem: SavedItem?
    @State private var duplicatePreview: SavedItem?
    @State private var errorMessage: String?
    @FocusState private var focusedField: ComposerField?

    private var recentTags: [String] {
        var seen = Set<String>()
        return existingItems
            .flatMap(\.tagNames)
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CreamCanvas()

                VStack(spacing: 0) {
                    header

                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            kindRow
                            contentBlock
                            thoughtBlock
                            tagBlock
                        }
                        .padding(.horizontal, MaybeMetrics.pageInset)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sensoryFeedback(.selection, trigger: kind)
            .safeAreaInset(edge: .bottom, spacing: 0) { saveBar }
            .photosPicker(
                isPresented: $isChoosingPhotos,
                selection: $photoSelections,
                maxSelectionCount: 12,
                matching: .images
            )
            .fileImporter(
                isPresented: $isChoosingFile,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false,
                onCompletion: importFile
            )
            .onChange(of: photoSelections) { _, selections in
                guard !selections.isEmpty else { return }
                loadPhotos(selections)
            }
            .task { preloadQAPhotosIfRequested() }
            .alert("Already in Maybe", isPresented: duplicateAlertBinding) {
                Button("Open the one you kept") {
                    duplicatePreview = duplicateItem
                    duplicateItem = nil
                }
                Button("Cancel", role: .cancel) { duplicateItem = nil }
            } message: {
                Text("“\(duplicateItem?.title ?? "It")” is already saved.")
            }
            .alert("Couldn’t save", isPresented: errorAlertBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
            .fullScreenCover(item: $duplicatePreview) { item in
                NavigationStack {
                    ItemDetailView(item: item)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") { duplicatePreview = nil }
                            }
                        }
                }
            }
        }
    }

    // MARK: Header and save bar

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(RoundKeycapButtonStyle(color: Color.white.opacity(0.75), size: 40))
            .accessibilityLabel("Close")

            Spacer()

            Text("Add")
                .font(.maybeRounded(19, weight: .black))
                .foregroundStyle(MaybePalette.ink)

            Spacer()

            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, MaybeMetrics.pageInset)
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    private var saveBar: some View {
        Button(action: save) {
            Text(isSaving ? "Saving…" : "Save to Inbox")
        }
        .buttonStyle(
            KeycapButtonStyle(
                color: canSave ? MaybePalette.yellow : Color.white.opacity(0.5),
                cornerRadius: 20,
                minHeight: 54
            )
        )
        .disabled(isSaving || !canSave)
        .opacity(canSave ? 1 : 0.75)
        .accessibilityIdentifier("save-maybe-button")
        .padding(.horizontal, MaybeMetrics.pageInset)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(MaybePalette.cream.opacity(0.94))
    }

    // MARK: Kind

    private var kindRow: some View {
        HStack(spacing: 8) {
            ForEach(MaybeKind.allCases) { option in
                Button {
                    kind = option
                    // Choosing Note or Link is choosing to type: skip the extra tap.
                    switch option {
                    case .note: focusedField = .note
                    case .link: focusedField = .link
                    case .photo, .file: focusedField = nil
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: option.symbol)
                            .font(.system(size: 17, weight: .bold))
                        Text(option.title)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(MaybePalette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background {
                        KeycapSurface(
                            color: kind == option ? option.accent : Color.white.opacity(0.6),
                            cornerRadius: 16,
                            depth: kind == option ? 2 : 3
                        )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.96))
                .accessibilityIdentifier("kind-\(option.rawValue)")
                .accessibilityAddTraits(kind == option ? .isSelected : [])
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var contentBlock: some View {
        switch kind {
        case .photo:
            photoBlock
        case .link:
            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("Link")
                TextField("https://", text: $sourceURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .focused($focusedField, equals: .link)
                    .padding(16)
                    .maybePanel(cornerRadius: 18)
                nameField
            }
        case .note:
            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("Note")
                TextField("Something worth keeping…", text: $name, axis: .vertical)
                    .lineLimit(4...10)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .focused($focusedField, equals: .note)
                    .padding(16)
                    .maybePanel(cornerRadius: 18)
            }
        case .file:
            VStack(alignment: .leading, spacing: 10) {
                fieldLabel("File")
                Button {
                    isChoosingFile = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: filePayload == nil ? "doc.badge.plus" : "doc.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text(fileName ?? "Choose a file")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(MaybePalette.inkFaint)
                    }
                    .foregroundStyle(MaybePalette.ink)
                    .padding(16)
                    .maybePanel(cornerRadius: 18)
                }
                .buttonStyle(PressableStyle())
                nameField
            }
        }
    }

    private var photoBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                fieldLabel(photoDrafts.isEmpty ? "Photos" : "\(photoDrafts.count) selected")
                if isLoadingPhotos {
                    ProgressView().controlSize(.small)
                }
                Spacer(minLength: 0)
                if !photoDrafts.isEmpty {
                    Button("Clear") {
                        withAnimation(.snappy(duration: 0.25)) {
                            photoDrafts = []
                        }
                        photoSelections = []
                    }
                    .font(.maybeMeta)
                    .foregroundStyle(MaybePalette.ink)
                }
            }

            if photoDrafts.isEmpty {
                Button {
                    isChoosingPhotos = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 24, weight: .bold))
                        Text("Choose photos")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("Up to 12, kept on this device")
                            .font(.system(size: 12))
                            .foregroundStyle(MaybePalette.inkSoft)
                    }
                    .foregroundStyle(MaybePalette.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 132)
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(MaybePalette.blue.opacity(0.16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .strokeBorder(
                                        MaybePalette.ink.opacity(0.18),
                                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                                    )
                            }
                    }
                }
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("choose-photos-button")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photoDrafts) { draft in
                            photoThumbnail(draft)
                        }

                        if photoDrafts.count < 12 {
                            Button {
                                isChoosingPhotos = true
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(MaybePalette.ink)
                                    .frame(width: 84, height: 106)
                                    .background {
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(MaybePalette.blue.opacity(0.16))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                    .strokeBorder(
                                                        MaybePalette.ink.opacity(0.18),
                                                        style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                                                    )
                                            }
                                    }
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel("Add more photos")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .contentMargins(.horizontal, 0, for: .scrollContent)

                nameField
            }
        }
    }

    private func photoThumbnail(_ draft: PhotoDraft) -> some View {
        Image(uiImage: draft.preview)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 84, height: 106)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .transition(.scale(scale: 0.85).combined(with: .opacity))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(MaybePalette.hairline, lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        photoDrafts.removeAll { $0.id == draft.id }
                    }
                    MaybeHaptics.removed()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(MaybePalette.ink)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.85), in: Circle())
                        .overlay(Circle().strokeBorder(MaybePalette.hairline, lineWidth: 1))
                }
                .buttonStyle(PressableStyle(scale: 0.9))
                .padding(6)
                .accessibilityLabel("Remove photo")
            }
    }

    private var nameField: some View {
        TextField("Name it (optional)", text: $name)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .padding(16)
            .maybePanel(cornerRadius: 18)
    }

    // MARK: Thought and tags

    private var thoughtBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("What caught you?")
            TextField("The way the light sits on the edge…", text: $thought, axis: .vertical)
                .lineLimit(2...6)
                .font(.system(size: 16))
                .focused($focusedField, equals: .thought)
                .padding(16)
                .maybePanel(cornerRadius: 18)
                .accessibilityIdentifier("thought-field")
        }
    }

    private var tagBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Tags")
            TagEditor(tags: $selectedTags, suggestions: recentTags)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.maybeSectionTitle)
            .foregroundStyle(MaybePalette.ink)
    }

    // MARK: Actions

    private func loadPhotos(_ selections: [PhotosPickerItem]) {
        isLoadingPhotos = true
        Task {
            var loaded: [PhotoDraft] = []
            for selection in selections {
                guard photoDrafts.count + loaded.count < 12 else { break }
                guard let data = try? await selection.loadTransferable(type: Data.self),
                      let draft = makeDraft(from: data) else { continue }
                loaded.append(draft)
            }
            withAnimation(.snappy(duration: 0.28)) {
                photoDrafts.append(contentsOf: loaded)
            }
            photoSelections = []
            isLoadingPhotos = false
        }
    }

    private func makeDraft(from data: Data) -> PhotoDraft? {
        guard let image = UIImage(data: data) else { return nil }
        let preview = image.preparingThumbnail(of: CGSize(width: 400, height: 400)) ?? image
        let size = MediaIngest.pixelSize(of: data)
        let aspect = size.height > 0 ? size.width / size.height : 1
        return PhotoDraft(data: data, preview: preview, aspect: aspect)
    }

    private func preloadQAPhotosIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--qa-composer-photos"), photoDrafts.isEmpty else { return }
        let sizes = [(1200, 1600), (1600, 1100), (1080, 1080)]
        for (index, size) in sizes.enumerated() {
            guard let data = SamplePhotoFactory.jpeg(width: size.0, height: size.1, seed: index + 2),
                  let draft = makeDraft(from: data) else { continue }
            photoDrafts.append(draft)
        }
        thought = "The way the light sits on the top edge."
        selectedTags = ["UI", "Glass"]
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            filePayload = try Data(contentsOf: url)
            fileName = url.lastPathComponent
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var canSave: Bool {
        switch kind {
        case .photo:
            return !photoDrafts.isEmpty
        case .link:
            guard let url = URL(string: sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
            return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        case .note:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !thought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .file:
            return filePayload != nil
        }
    }

    private var duplicateAlertBinding: Binding<Bool> {
        Binding(get: { duplicateItem != nil }, set: { if !$0 { duplicateItem = nil } })
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var resolvedTitle: String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return String(typed.prefix(120)) }

        let thoughtText = thought.trimmingCharacters(in: .whitespacesAndNewlines)
        if !thoughtText.isEmpty { return String(thoughtText.prefix(80)) }

        switch kind {
        case .photo:
            return photoDrafts.count > 1 ? "\(photoDrafts.count) photos" : "Photo"
        case .link:
            return URL(string: sourceURL)?.host() ?? "Link"
        case .note:
            return "Note"
        case .file:
            return fileName ?? "File"
        }
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }

        do {
            let payloads: [Data] = kind == .photo
                ? photoDrafts.map(\.data)
                : (filePayload.map { [$0] } ?? [])

            let attachments = try modelContext.fetch(FetchDescriptor<MediaAttachment>())
            for payload in payloads {
                let hash = LocalMediaStore.hash(payload)
                if let duplicate = attachments.first(where: { $0.sha256 == hash }), let owner = duplicate.item {
                    duplicateItem = owner
                    MaybeHaptics.blocked()
                    return
                }
            }

            let trimmedSource = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if kind == .link {
                let normalized = normalizedLink(trimmedSource)
                if let existing = existingItems.first(where: { normalizedLink($0.sourceURLString ?? "") == normalized }) {
                    duplicateItem = existing
                    MaybeHaptics.blocked()
                    return
                }
            }

            let thoughtText = thought.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = resolvedTitle
            let item = SavedItem(
                kind: kind,
                title: title,
                note: thoughtText == title ? "" : thoughtText,
                sourceURLString: trimmedSource.isEmpty ? nil : trimmedSource,
                isInbox: true,
                tagNames: selectedTags,
                accentHex: MaybePalette.accentHex(at: existingItems.count)
            )
            modelContext.insert(item)

            if kind == .photo {
                for (index, draft) in photoDrafts.enumerated() {
                    try MediaIngest.attach(
                        draft.data,
                        kind: .image,
                        filename: LocalMediaStore.photoFilename(index: index),
                        to: item
                    )
                }
            } else if let filePayload {
                try MediaIngest.attach(
                    filePayload,
                    kind: .file,
                    filename: fileName ?? "attachment",
                    to: item
                )
            }

            try modelContext.save()
            MaybeHaptics.saved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func normalizedLink(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}

extension MaybeKind {
    var accent: Color {
        switch self {
        case .photo: MaybePalette.blue
        case .link: MaybePalette.green
        case .note: MaybePalette.yellow
        case .file: MaybePalette.purple
        }
    }
}

// MARK: - New idea

struct NewIdeaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedItem.createdAt, order: .reverse) private var items: [SavedItem]

    let preselectedItem: SavedItem?
    @State private var title = ""
    @State private var note = ""
    @State private var selectedIDs: Set<UUID>
    @State private var errorMessage: String?

    init(preselectedItem: SavedItem?) {
        self.preselectedItem = preselectedItem
        _selectedIDs = State(initialValue: Set(preselectedItem.map { [$0.id] } ?? []))
    }

    private var selectedItems: [SavedItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CreamCanvas()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Name the idea", text: $title)
                                .font(.maybeRounded(24, weight: .black))
                                .padding(16)
                                .maybePanel(cornerRadius: 20)
                                .accessibilityIdentifier("idea-title-field")

                            TextField("What could this become?", text: $note, axis: .vertical)
                                .lineLimit(2...5)
                                .font(.system(size: 16))
                                .padding(16)
                                .maybePanel(cornerRadius: 20)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(
                                title: "Inspired by",
                                count: selectedIDs.isEmpty ? nil : selectedIDs.count
                            )

                            if items.isEmpty {
                                EmptyLibraryView(symbol: "tray", title: "Save something first.")
                            } else {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 92), spacing: 10)],
                                    spacing: 10
                                ) {
                                    ForEach(items) { item in
                                        Button {
                                            toggle(item)
                                        } label: {
                                            pickerTile(item)
                                        }
                                        .buttonStyle(PressableStyle())
                                        .accessibilityLabel(item.title)
                                        .accessibilityAddTraits(selectedIDs.contains(item.id) ? .isSelected : [])
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, MaybeMetrics.pageInset)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: save) {
                    Text("Create idea")
                }
                .buttonStyle(
                    KeycapButtonStyle(
                        color: canSave ? MaybePalette.green : Color.white.opacity(0.5),
                        cornerRadius: 20,
                        minHeight: 54
                    )
                )
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.75)
                .accessibilityIdentifier("create-idea-button")
                .padding(.horizontal, MaybeMetrics.pageInset)
                .padding(.vertical, 10)
                .background(MaybePalette.cream.opacity(0.94))
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

    private func pickerTile(_ item: SavedItem) -> some View {
        let isSelected = selectedIDs.contains(item.id)
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { ItemPreview(item: item, size: .compact) }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? MaybePalette.ink : MaybePalette.hairline, lineWidth: isSelected ? 2.5 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(MaybePalette.ink)
                        .frame(width: 24, height: 24)
                        .background(MaybePalette.green, in: Circle())
                        .overlay(Circle().strokeBorder(MaybePalette.ink.opacity(0.2), lineWidth: 1))
                        .padding(6)
                }
            }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func toggle(_ item: SavedItem) {
        withAnimation(.snappy(duration: 0.2)) {
            if selectedIDs.contains(item.id) {
                selectedIDs.remove(item.id)
            } else {
                selectedIDs.insert(item.id)
            }
        }
    }

    private func save() {
        let chosen = selectedItems
        let idea = Idea(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            coverItemID: chosen.first(where: { $0.primaryImage != nil })?.id ?? chosen.first?.id,
            tagNames: Array(Set(chosen.flatMap(\.tagNames))).sorted(),
            accentHex: MaybePalette.accentHex(at: chosen.count),
            items: chosen
        )
        modelContext.insert(idea)
        for item in chosen {
            item.isInbox = false
            item.modifiedAt = .now
        }

        do {
            try modelContext.save()
            let titles = (try modelContext.fetch(FetchDescriptor<Idea>())).map(\.title)
            MaybeSharedContainer.publishIdeaTitles(titles)
            MaybeHaptics.saved()
            dismiss()
        } catch {
            modelContext.delete(idea)
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Item detail

struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let item: SavedItem

    @State private var ideaSeed: SavedItem?
    @State private var isEditing = false
    @State private var isAddingToIdea = false
    @State private var fullScreenIndex: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                VStack(alignment: .leading, spacing: 22) {
                    titleBlock

                    if !item.note.isEmpty {
                        panel(title: "Why I saved this") {
                            Text(item.note)
                                .font(.system(size: 16))
                                .foregroundStyle(MaybePalette.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if !item.tagNames.isEmpty {
                        FlowLayout(spacing: 8, rowSpacing: 8) {
                            ForEach(item.tagNames, id: \.self) { tag in
                                TagChip(name: tag, color: Color(hex: item.accentHex), selected: true)
                            }
                        }
                    }

                    if !item.ideas.isEmpty {
                        panel(title: "Used in") {
                            VStack(spacing: 8) {
                                ForEach(item.ideas) { idea in
                                    NavigationLink {
                                        IdeaDetailView(idea: idea)
                                    } label: {
                                        HStack {
                                            Text(idea.title)
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(MaybePalette.inkFaint)
                                        }
                                        .foregroundStyle(MaybePalette.ink)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PressableStyle())
                                }
                            }
                        }
                    }

                    if let source = item.sourceURLString, let url = URL(string: source) {
                        panel(title: "From") {
                            Link(destination: url) {
                                HStack {
                                    Text(item.hostName ?? source)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundStyle(MaybePalette.ink)
                            }
                        }
                    }

                    if let attachment = item.media.first(where: { $0.type == .file }) {
                        panel(title: "File") {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(attachment.originalFilename)
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .lineLimit(2)
                                    Text("On this device only")
                                        .font(.maybeMeta)
                                        .foregroundStyle(MaybePalette.inkSoft)
                                }
                                Spacer(minLength: 0)
                                ShareLink(item: LocalMediaStore().url(at: attachment.localPath)) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(MaybePalette.ink)
                                        .frame(width: 42, height: 42)
                                        .background { KeycapSurface(color: Color.white.opacity(0.7), cornerRadius: 14, depth: 2) }
                                }
                                .accessibilityLabel("Share this file")
                            }
                        }
                    }

                    actions
                }
                .padding(.horizontal, MaybeMetrics.pageInset)
            }
            .padding(.bottom, 28)
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
                .accessibilityLabel("Edit")
                .accessibilityIdentifier("edit-item-button")
            }
        }
        .task {
            item.lastViewedAt = .now
            try? modelContext.save()
        }
        .sheet(item: $ideaSeed) { seed in
            NewIdeaSheet(preselectedItem: seed)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $isEditing) {
            EditItemSheet(item: item, onDeleted: { dismiss() })
                .presentationDetents([.large])
        }
        .sheet(isPresented: $isAddingToIdea) {
            AddToIdeaSheet(item: item)
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: fullScreenBinding) { index in
            PhotoViewer(images: item.images, startIndex: index.value, title: item.title)
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var hero: some View {
        let images = item.images
        if images.isEmpty {
            Color.clear
                .aspectRatio(item.previewAspect, contentMode: .fit)
                .overlay { ItemPreview(item: item) }
                .frame(maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(.horizontal, MaybeMetrics.pageInset)
                .padding(.top, 4)
        } else if images.count == 1 {
            photoPage(images[0], index: 0, count: 1)
                .frame(height: heroHeight)
                .padding(.top, 4)
        } else {
            TabView {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, attachment in
                    photoPage(attachment, index: index, count: images.count)
                        .padding(.bottom, 34)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: heroHeight + 34)
            .padding(.top, 4)
        }
    }

    private var heroHeight: CGFloat {
        guard let image = item.primaryImage, image.width > 0, image.height > 0 else { return 300 }
        let ratio = MediaAspect.ratio(width: image.width, height: image.height)
        // Portrait photos get more room, landscape ones less, but nothing is cropped.
        return min(430, max(240, 360 / ratio))
    }

    private func photoPage(_ attachment: MediaAttachment, index: Int, count: Int) -> some View {
        Button {
            fullScreenIndex = index
        } label: {
            LocalAttachmentImage(
                attachment: attachment,
                accessibilityTitle: count > 1 ? "\(item.title), photo \(index + 1) of \(count)" : item.title,
                prefersOriginal: true,
                contentMode: .fit
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(MaybePalette.hairline, lineWidth: 1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, MaybeMetrics.pageInset)
        }
        .buttonStyle(PressableStyle(scale: 0.99))
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.maybeRounded(26, weight: .black))
                    .foregroundStyle(MaybePalette.ink)
                    .multilineTextAlignment(.leading)

                Text(metaLine)
                    .font(.maybeMeta)
                    .foregroundStyle(MaybePalette.inkSoft)
            }

            Spacer(minLength: 0)

            Button {
                item.isFavorite.toggle()
                item.modifiedAt = .now
                try? modelContext.save()
            } label: {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(item.isFavorite ? MaybePalette.coral : MaybePalette.ink)
                    .symbolEffect(.bounce, value: item.isFavorite)
            }
            .buttonStyle(RoundKeycapButtonStyle(color: Color.white.opacity(0.75), size: 46))
            .accessibilityLabel(item.isFavorite ? "Remove favourite" : "Favourite")
        }
    }

    private var metaLine: String {
        var parts = [item.kind.title]
        if item.imageCount > 1 { parts.append("\(item.imageCount) photos") }
        parts.append(item.createdAt.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                isAddingToIdea = true
            } label: {
                Text("Add to an idea")
            }
            .buttonStyle(KeycapButtonStyle(color: MaybePalette.purple, cornerRadius: 20))

            Button {
                ideaSeed = item
            } label: {
                Text("Make a new idea from this")
            }
            .buttonStyle(KeycapButtonStyle(color: Color.white.opacity(0.7), cornerRadius: 20))
        }
    }

    private func panel<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(MaybePalette.inkSoft)
                .textCase(.uppercase)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .maybePanel()
    }

    private var fullScreenBinding: Binding<IdentifiableIndex?> {
        Binding(
            get: { fullScreenIndex.map(IdentifiableIndex.init) },
            set: { fullScreenIndex = $0?.value }
        )
    }
}

struct IdentifiableIndex: Identifiable {
    let value: Int
    var id: Int { value }
}

// MARK: - Idea detail

struct IdeaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let idea: Idea
    @State private var isEditing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(idea.title)
                        .font(.maybeRounded(30, weight: .black))
                        .foregroundStyle(MaybePalette.ink)

                    if !idea.note.isEmpty {
                        Text(idea.note)
                            .font(.system(size: 16))
                            .foregroundStyle(MaybePalette.inkSoft)
                    }
                }

                if !idea.tagNames.isEmpty {
                    FlowLayout(spacing: 8, rowSpacing: 8) {
                        ForEach(idea.tagNames, id: \.self) { tag in
                            TagChip(name: tag, color: Color(hex: idea.accentHex), selected: true)
                        }
                    }
                }

                if idea.items.isEmpty {
                    EmptyLibraryView(symbol: "square.grid.2x2", title: "Nothing linked to this idea yet.")
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Inspired by", count: idea.items.count)
                        MasonryGrid(items: idea.items) { $0.previewAspect } content: { item in
                            NavigationLink {
                                ItemDetailView(item: item)
                            } label: {
                                ItemTile(item: item)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, MaybeMetrics.pageInset)
            .padding(.top, 8)
            .padding(.bottom, 28)
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
                .accessibilityLabel("Edit idea")
            }
        }
        .sheet(isPresented: $isEditing) {
            EditIdeaSheet(idea: idea, onDeleted: { dismiss() })
                .presentationDetents([.large])
        }
    }
}

// MARK: - Surprise

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

            VStack(spacing: 18) {
                HStack {
                    Text("Maybe?")
                        .font(.maybeRounded(26, weight: .black))
                        .foregroundStyle(MaybePalette.ink)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(RoundKeycapButtonStyle(color: Color.white.opacity(0.75), size: 44))
                    .accessibilityLabel("Close")
                }

                ItemPreview(item: currentItem, prefersOriginal: true, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(MaybePalette.hairline, lineWidth: 1)
                    }
                    .shadow(color: MaybePalette.ink.opacity(0.12), radius: 2, y: 3)
                    .frame(maxWidth: .infinity, maxHeight: 470)

                VStack(alignment: .leading, spacing: 6) {
                    Text(currentItem.title)
                        .font(.maybeRounded(22, weight: .bold))
                        .foregroundStyle(MaybePalette.ink)
                    if !currentItem.note.isEmpty {
                        Text(currentItem.note)
                            .font(.system(size: 15))
                            .foregroundStyle(MaybePalette.inkSoft)
                    }
                    Text("Saved \(currentItem.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.maybeMeta)
                        .foregroundStyle(MaybePalette.inkFaint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button {
                        currentItem.isFavorite = true
                        currentItem.modifiedAt = .now
                        try? modelContext.save()
                        MaybeHaptics.saved()
                    } label: {
                        Image(systemName: "heart.fill")
                            .symbolEffect(.bounce, value: currentItem.isFavorite)
                    }
                    .buttonStyle(KeycapButtonStyle(color: MaybePalette.coral, cornerRadius: 18))
                    .accessibilityLabel("Keep around")

                    Button {
                        isAddingToIdea = true
                    } label: {
                        Image(systemName: "lightbulb.fill")
                    }
                    .buttonStyle(KeycapButtonStyle(color: MaybePalette.green, cornerRadius: 18))
                    .accessibilityLabel("Add to an idea")

                    Button {
                        if let next = items.filter({ $0.id != currentItem.id }).randomElement() {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                currentItem = next
                            }
                        }
                    } label: {
                        Text("Next")
                    }
                    .buttonStyle(KeycapButtonStyle(color: MaybePalette.blue, cornerRadius: 18))
                }
            }
            .padding(MaybeMetrics.pageInset)
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

// MARK: - Photo viewer

struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let images: [MediaAttachment]
    let startIndex: Int
    let title: String

    @State private var index: Int = 0

    var body: some View {
        NavigationStack {
            ZStack {
                MaybePalette.ink.ignoresSafeArea()

                TabView(selection: $index) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { offset, attachment in
                        LocalAttachmentImage(
                            attachment: attachment,
                            accessibilityTitle: "\(title), photo \(offset + 1)",
                            prefersOriginal: true,
                            contentMode: .fit
                        )
                        .tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
            }
            .navigationTitle(images.count > 1 ? "\(index + 1) of \(images.count)" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if images.indices.contains(index) {
                        ShareLink(item: LocalMediaStore().url(at: images[index].localPath)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share photo")
                    }
                }
            }
        }
        .task { index = startIndex }
    }
}
