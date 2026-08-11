import PhotosUI
import SwiftData
import SwiftUI

// MARK: - Add to idea

struct AddToIdeaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Idea.modifiedAt, order: .reverse) private var ideas: [Idea]

    let item: SavedItem
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                CreamCanvas()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if ideas.isEmpty {
                            EmptyLibraryView(symbol: "lightbulb", title: "No ideas yet.")
                        } else {
                            ForEach(ideas) { idea in
                                let alreadyThere = idea.items.contains { $0.id == item.id }
                                Button {
                                    add(to: idea)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: alreadyThere ? "checkmark" : "lightbulb.fill")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(MaybePalette.ink)
                                            .frame(width: 46, height: 46)
                                            .background {
                                                KeycapSurface(
                                                    color: Color(hex: idea.accentHex).opacity(0.85),
                                                    cornerRadius: 14,
                                                    depth: 2
                                                )
                                            }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(idea.title)
                                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                                .foregroundStyle(MaybePalette.ink)
                                            Text("Inspired by \(idea.items.count)")
                                                .font(.maybeMeta)
                                                .foregroundStyle(MaybePalette.inkSoft)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(12)
                                    .maybePanel(cornerRadius: 20)
                                    .opacity(alreadyThere ? 0.55 : 1)
                                }
                                .buttonStyle(PressableStyle())
                                .disabled(alreadyThere)
                            }
                        }
                    }
                    .padding(.horizontal, MaybeMetrics.pageInset)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Add to idea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn’t update the idea", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func add(to idea: Idea) {
        do {
            try LibraryMutationService.add(item, to: idea, in: modelContext)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Edit a saved thing

struct EditItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedItem.modifiedAt, order: .reverse) private var allItems: [SavedItem]

    let item: SavedItem
    var onDeleted: () -> Void = {}

    @State private var title: String
    @State private var note: String
    @State private var source: String
    @State private var tags: [String]
    @State private var isFavorite: Bool
    @State private var isInbox: Bool
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var isChoosingPhotos = false
    @State private var isConfirmingDelete = false
    @State private var removalCandidate: MediaAttachment?
    @State private var errorMessage: String?

    init(item: SavedItem, onDeleted: @escaping () -> Void = {}) {
        self.item = item
        self.onDeleted = onDeleted
        _title = State(initialValue: item.title)
        _note = State(initialValue: item.note)
        _source = State(initialValue: item.sourceURLString ?? "")
        _tags = State(initialValue: item.tagNames)
        _isFavorite = State(initialValue: item.isFavorite)
        _isInbox = State(initialValue: item.isInbox)
    }

    private var suggestions: [String] {
        var seen = Set<String>()
        return allItems
            .flatMap(\.tagNames)
            .filter { seen.insert($0.lowercased()).inserted }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CreamCanvas()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if item.kind != .file {
                            photosSection
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            label("Name")
                            TextField("Name", text: $title)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .padding(16)
                                .maybePanel(cornerRadius: 18)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            label("What caught you?")
                            TextField("Why this one?", text: $note, axis: .vertical)
                                .lineLimit(3...8)
                                .font(.system(size: 16))
                                .padding(16)
                                .maybePanel(cornerRadius: 18)
                        }

                        if item.kind == .link || !source.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                label("Source")
                                TextField("https://", text: $source)
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .padding(16)
                                    .maybePanel(cornerRadius: 18)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            label("Tags")
                            TagEditor(tags: $tags, suggestions: suggestions)
                        }

                        VStack(spacing: 0) {
                            Toggle("Favourite", isOn: $isFavorite)
                                .padding(16)
                            Divider().padding(.horizontal, 16)
                            Toggle("Keep in Inbox", isOn: $isInbox)
                                .padding(16)
                        }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(MaybePalette.ink)
                        .tint(MaybePalette.purple)
                        .maybePanel(cornerRadius: 20)

                        Button("Delete this Maybe", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .buttonStyle(KeycapButtonStyle(color: MaybePalette.coral.opacity(0.85), cornerRadius: 18))
                    }
                    .padding(.horizontal, MaybeMetrics.pageInset)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .photosPicker(
                isPresented: $isChoosingPhotos,
                selection: $photoSelections,
                maxSelectionCount: 12,
                matching: .images
            )
            .onChange(of: photoSelections) { _, selections in
                guard !selections.isEmpty else { return }
                addPhotos(selections)
            }
            .confirmationDialog("Delete this Maybe?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its local media is removed too.")
            }
            .confirmationDialog("Remove this photo?", isPresented: removalBinding, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { removeSelectedPhoto() }
                Button("Cancel", role: .cancel) { removalCandidate = nil }
            }
            .alert("Couldn’t save changes", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            label(item.imageCount == 0 ? "Photos" : "\(item.imageCount) photo\(item.imageCount == 1 ? "" : "s")")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(item.images) { attachment in
                        LocalAttachmentImage(attachment: attachment, accessibilityTitle: item.title)
                            .frame(width: 92, height: 112)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(MaybePalette.hairline, lineWidth: 1)
                            }
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    removalCandidate = attachment
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

                    if item.imageCount < 12 {
                        Button {
                            isChoosingPhotos = true
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .bold))
                                Text("Add")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(MaybePalette.ink)
                            .frame(width: 92, height: 112)
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
                        .accessibilityIdentifier("add-photos-button")
                    }
                }
                .padding(.vertical, 4)
            }
            .contentMargins(.horizontal, 0, for: .scrollContent)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.maybeSectionTitle)
            .foregroundStyle(MaybePalette.ink)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { removalCandidate != nil }, set: { if !$0 { removalCandidate = nil } })
    }

    private func addPhotos(_ selections: [PhotosPickerItem]) {
        Task {
            var payloads: [Data] = []
            for selection in selections {
                guard let data = try? await selection.loadTransferable(type: Data.self) else { continue }
                payloads.append(data)
            }
            photoSelections = []
            guard !payloads.isEmpty else { return }
            do {
                try LibraryMutationService.addPhotos(payloads, to: item, in: modelContext)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeSelectedPhoto() {
        guard let attachment = removalCandidate else { return }
        do {
            try LibraryMutationService.removeMedia(attachment, from: item, in: modelContext)
            removalCandidate = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            item.isFavorite = isFavorite
            let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
            try LibraryMutationService.update(
                item,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceURLString: trimmedSource.isEmpty ? nil : trimmedSource,
                tagNames: tags,
                isInbox: isInbox,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        do {
            try LibraryMutationService.delete(item, in: modelContext)
            dismiss()
            onDeleted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Edit an idea

struct EditIdeaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedItem.createdAt, order: .reverse) private var items: [SavedItem]

    let idea: Idea
    var onDeleted: () -> Void = {}

    @State private var title: String
    @State private var note: String
    @State private var tags: [String]
    @State private var selectedIDs: Set<UUID>
    @State private var coverItemID: UUID?
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    init(idea: Idea, onDeleted: @escaping () -> Void = {}) {
        self.idea = idea
        self.onDeleted = onDeleted
        _title = State(initialValue: idea.title)
        _note = State(initialValue: idea.note)
        _tags = State(initialValue: idea.tagNames)
        _selectedIDs = State(initialValue: Set(idea.items.map(\.id)))
        _coverItemID = State(initialValue: idea.coverItemID)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CreamCanvas()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Idea name", text: $title)
                                .font(.maybeRounded(22, weight: .black))
                                .padding(16)
                                .maybePanel(cornerRadius: 20)

                            TextField("What could this become?", text: $note, axis: .vertical)
                                .lineLimit(2...6)
                                .font(.system(size: 16))
                                .padding(16)
                                .maybePanel(cornerRadius: 20)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tags")
                                .font(.maybeSectionTitle)
                                .foregroundStyle(MaybePalette.ink)
                            TagEditor(tags: $tags)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Inspired by", count: selectedIDs.count)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                                ForEach(items) { item in
                                    Button {
                                        toggle(item)
                                    } label: {
                                        tile(item)
                                    }
                                    .buttonStyle(PressableStyle())
                                    .accessibilityLabel(item.title)
                                    .accessibilityAddTraits(selectedIDs.contains(item.id) ? .isSelected : [])
                                }
                            }
                        }

                        if selectedIDs.count > 1 {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Cover")
                                    .font(.maybeSectionTitle)
                                    .foregroundStyle(MaybePalette.ink)
                                Picker("Cover", selection: $coverItemID) {
                                    Text("Automatic").tag(UUID?.none)
                                    ForEach(items.filter { selectedIDs.contains($0.id) }) { item in
                                        Text(item.title).tag(UUID?.some(item.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(MaybePalette.ink)
                                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                                .padding(.horizontal, 14)
                                .maybePanel(cornerRadius: 18)
                            }
                        }

                        Button("Delete this idea", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .buttonStyle(KeycapButtonStyle(color: MaybePalette.coral.opacity(0.85), cornerRadius: 18))
                    }
                    .padding(.horizontal, MaybeMetrics.pageInset)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Edit idea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Delete this idea?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The things inside it stay in Maybe.")
            }
            .alert("Couldn’t save changes", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private func tile(_ item: SavedItem) -> some View {
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

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func toggle(_ item: SavedItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
            if coverItemID == item.id { coverItemID = nil }
        } else {
            selectedIDs.insert(item.id)
        }
    }

    private func save() {
        do {
            try LibraryMutationService.update(
                idea,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                tagNames: tags,
                itemIDs: selectedIDs,
                coverItemID: coverItemID,
                from: items,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        do {
            try LibraryMutationService.delete(idea, in: modelContext)
            dismiss()
            onDeleted()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
