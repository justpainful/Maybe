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
    private let typeColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)

    private var recentTags: [String] {
        var seen = Set<String>()
        return existingItems
            .flatMap(\.tagNames)
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CreamCanvas()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        typePicker
                        contentInput
                        thoughtInput
                        tagsInput
                    }
                    .padding(.horizontal, MaybeMetrics.pageInset)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                }
            }
            .navigationTitle("Add to Maybe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: save) {
                    HStack {
                        if isSaving {
                            ProgressView().tint(MaybePalette.ink)
                        } else {
                            Image(systemName: "arrow.down.to.line.compact")
                        }
                        Text(isSaving ? "Saving…" : "Save to Inbox")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(KeycapButtonStyle(color: MaybePalette.yellow, cornerRadius: 20, depth: 3))
                .disabled(isSaving)
                .accessibilityIdentifier("save-maybe-button")
                .padding(.horizontal, MaybeMetrics.pageInset)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
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

    private var typePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What are you keeping?")
                .font(.maybeRounded(21, weight: .bold))

            LazyVGrid(columns: typeColumns, spacing: 10) {
                ForEach(MaybeKind.allCases) { option in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            kind = option
                        }
                    } label: {
                        Label(option.title, systemImage: option.symbol)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(
                        KeycapButtonStyle(
                            color: kind == option ? accent(for: option) : MaybePalette.glassWhite,
                            cornerRadius: 17,
                            depth: 3
                        )
                    )
                    .accessibilityIdentifier("kind-\(option.rawValue)")
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
                TagGrid(tags: recentTags, accent: MaybePalette.green)
            }
        }
    }

    private func inputCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            .maybeGlass(cornerRadius: 21)
    }

    private func accent(for kind: MaybeKind) -> Color {
        switch kind {
        case .photo: MaybePalette.blue
        case .link: MaybePalette.green
        case .note: MaybePalette.yellow
        case .file: MaybePalette.purple
        }
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

private struct MaybePickerSurface: View {
    let symbol: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .bold))
                .frame(width: 58, height: 56)
                .background(color.opacity(0.72), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(MaybePalette.ink.opacity(0.54))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
        }
        .foregroundStyle(MaybePalette.ink)
        .padding(14)
        .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .maybeGlass(cornerRadius: 23, tint: color.opacity(0.12), interactive: true)
    }
}

struct NewIdeaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedItem.createdAt, order: .reverse) private var items: [SavedItem]

    let preselectedItem: SavedItem?
    @State private var title = ""
    @State private var note = ""
    @State private var selectedIDs: Set<UUID>

    init(preselectedItem: SavedItem?) {
        self.preselectedItem = preselectedItem
        _selectedIDs = State(initialValue: Set(preselectedItem.map { [$0.id] } ?? []))
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
                                        } else {
                                            selectedIDs.insert(item.id)
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
        }
    }

    private func save() {
        let selectedItems = items.filter { selectedIDs.contains($0.id) }
        let idea = Idea(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            coverItemID: selectedItems.first?.id,
            tagNames: Array(Set(selectedItems.flatMap(\.tagNames))).sorted(),
            accentHex: MaybePalette.accentHexes[selectedIDs.count % MaybePalette.accentHexes.count],
            items: selectedItems
        )
        modelContext.insert(idea)
        try? modelContext.save()
        let allIdeaTitles = ((try? modelContext.fetch(FetchDescriptor<Idea>())) ?? []).map(\.title)
        MaybeSharedContainer.publishIdeaTitles(allIdeaTitles)
        dismiss()
    }
}

struct ItemDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let item: SavedItem
    @State private var ideaSeed: SavedItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                InspirationThumbnail(item: item)
                    .frame(maxWidth: .infinity)
                    .frame(height: 420)
                    .clipped()

                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text(item.title)
                                .font(.maybeRounded(30, weight: .black))
                            Spacer()
                            Button {
                                item.isFavorite.toggle()
                                item.modifiedAt = .now
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

                    Button {
                        ideaSeed = item
                    } label: {
                        Label("Make an idea from this", systemImage: "lightbulb.max.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(KeycapButtonStyle(color: MaybePalette.yellow, cornerRadius: 22))
                }
                .padding(20)
                .padding(.bottom, 30)
                .background(MaybePalette.cream)
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            item.lastViewedAt = .now
            try? modelContext.save()
        }
        .sheet(item: $ideaSeed) { seed in
            NewIdeaSheet(preselectedItem: seed)
                .presentationDetents([.medium, .large])
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
    let idea: Idea
    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 13)]

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
    }
}

struct SurpriseView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [SavedItem]
    @State private var currentItem: SavedItem

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
                    } label: {
                        Label("Keep around", systemImage: "heart.fill")
                    }
                    .buttonStyle(KeycapButtonStyle(color: MaybePalette.coral, cornerRadius: 20))

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
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
