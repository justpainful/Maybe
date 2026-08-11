import SwiftData
import SwiftUI

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
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Choose where this belongs. Adding it also clears it from Inbox.")
                            .font(.subheadline)
                            .foregroundStyle(MaybePalette.ink.opacity(0.58))

                        if ideas.isEmpty {
                            EmptyLibraryView(
                                symbol: "lightbulb.max",
                                title: "No ideas yet",
                                message: "Create an idea first, then connect this Maybe to it."
                            )
                        } else {
                            ForEach(ideas) { idea in
                                Button {
                                    add(to: idea)
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: idea.items.contains(where: { $0.id == item.id }) ? "checkmark.circle.fill" : "lightbulb.fill")
                                            .font(.title3)
                                            .foregroundStyle(MaybePalette.ink)
                                            .frame(width: 46, height: 44)
                                            .glassEffect(.regular.tint(Color(hex: idea.accentHex).opacity(0.5)), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(idea.title)
                                                .font(.system(.headline, design: .rounded, weight: .bold))
                                            Text("Inspired by \(idea.items.count) things")
                                                .font(.caption)
                                                .foregroundStyle(MaybePalette.ink.opacity(0.56))
                                        }
                                        Spacer()
                                    }
                                    .padding(14)
                                    .foregroundStyle(MaybePalette.ink)
                                    .background(Color.white.opacity(0.26), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                    .maybeGlass(cornerRadius: 22, tint: Color(hex: idea.accentHex).opacity(0.1), interactive: true)
                                }
                                .buttonStyle(.plain)
                                .disabled(idea.items.contains(where: { $0.id == item.id }))
                            }
                        }
                    }
                    .padding(20)
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
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func add(to idea: Idea) {
        do {
            try LibraryMutationService.add(item, to: idea, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EditItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let item: SavedItem
    var onDeleted: () -> Void = {}

    @State private var title: String
    @State private var note: String
    @State private var source: String
    @State private var tags: String
    @State private var isFavorite: Bool
    @State private var isInbox: Bool
    @State private var isConfirmingDelete = false
    @State private var isShowingIdeas = false
    @State private var errorMessage: String?

    init(item: SavedItem, onDeleted: @escaping () -> Void = {}) {
        self.item = item
        self.onDeleted = onDeleted
        _title = State(initialValue: item.title)
        _note = State(initialValue: item.note)
        _source = State(initialValue: item.sourceURLString ?? "")
        _tags = State(initialValue: item.tagNames.joined(separator: ", "))
        _isFavorite = State(initialValue: item.isFavorite)
        _isInbox = State(initialValue: item.isInbox)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Maybe") {
                    TextField("Title", text: $title)
                    TextField("What caught you?", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                    if item.kind == .link {
                        TextField("Source URL", text: $source)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                    }
                }

                Section("Organize") {
                    TextField("Tags, separated by commas", text: $tags)
                    Toggle("Favorite", isOn: $isFavorite)
                    Toggle("Keep in Inbox", isOn: $isInbox)
                    Button {
                        isShowingIdeas = true
                    } label: {
                        Label("Add to an idea", systemImage: "lightbulb.max.fill")
                    }
                }

                if let attachment = item.media.first {
                    Section("File") {
                        LabeledContent("Name", value: attachment.originalFilename)
                        LabeledContent("Stored", value: "On this device")
                    }
                }

                Section {
                    Button("Delete Maybe", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } footer: {
                    Text("Deleting removes its local media too. Ideas that used it are preserved.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(CreamCanvas())
            .navigationTitle("Edit Maybe")
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
            .sheet(isPresented: $isShowingIdeas) {
                AddToIdeaSheet(item: item)
                    .presentationDetents([.medium, .large])
            }
            .confirmationDialog("Delete this Maybe?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
            .alert("Couldn’t save changes", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private var parsedTags: [String] {
        Array(Set(tags.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func save() {
        do {
            item.isFavorite = isFavorite
            try LibraryMutationService.update(
                item,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceURLString: source.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                tagNames: parsedTags,
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

struct EditIdeaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedItem.createdAt, order: .reverse) private var items: [SavedItem]

    let idea: Idea
    var onDeleted: () -> Void = {}

    @State private var title: String
    @State private var note: String
    @State private var tags: String
    @State private var selectedIDs: Set<UUID>
    @State private var coverItemID: UUID?
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    init(idea: Idea, onDeleted: @escaping () -> Void = {}) {
        self.idea = idea
        self.onDeleted = onDeleted
        _title = State(initialValue: idea.title)
        _note = State(initialValue: idea.note)
        _tags = State(initialValue: idea.tagNames.joined(separator: ", "))
        _selectedIDs = State(initialValue: Set(idea.items.map(\.id)))
        _coverItemID = State(initialValue: idea.coverItemID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Idea") {
                    TextField("Idea name", text: $title)
                    TextField("What could this become?", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Tags, separated by commas", text: $tags)
                }

                Section {
                    ForEach(items) { item in
                        Button {
                            toggle(item)
                        } label: {
                            HStack(spacing: 12) {
                                InspirationThumbnail(item: item)
                                    .frame(width: 54, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                Text(item.title)
                                    .foregroundStyle(MaybePalette.ink)
                                Spacer()
                                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(item.id) ? MaybePalette.purple : MaybePalette.ink.opacity(0.3))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(selectedIDs.contains(item.id) ? "Selected" : "Not selected")
                    }
                } header: {
                    Text("Inspired by")
                } footer: {
                    Text("Select the things that shape this idea.")
                }

                if !selectedIDs.isEmpty {
                    Section("Cover") {
                        Picker("Cover Maybe", selection: $coverItemID) {
                            Text("Automatic").tag(UUID?.none)
                            ForEach(items.filter { selectedIDs.contains($0.id) }) { item in
                                Text(item.title).tag(UUID?.some(item.id))
                            }
                        }
                    }
                }

                Section {
                    Button("Delete Idea", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } footer: {
                    Text("The saved things inside it will not be deleted.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(CreamCanvas())
            .navigationTitle("Edit Idea")
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
                Text("Its saved things will stay in Maybe.")
            }
            .alert("Couldn’t save changes", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private var parsedTags: [String] {
        Array(Set(tags.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })).sorted()
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func toggle(_ item: SavedItem) {
        if selectedIDs.remove(item.id) == nil {
            selectedIDs.insert(item.id)
        } else if coverItemID == item.id {
            coverItemID = nil
        }
    }

    private func save() {
        do {
            try LibraryMutationService.update(
                idea,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                tagNames: parsedTags,
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

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
