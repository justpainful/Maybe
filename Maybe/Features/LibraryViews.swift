import SwiftData
import SwiftUI

// MARK: - Home

struct HomeView: View {
    @Query(sort: \SavedItem.createdAt, order: .reverse) private var items: [SavedItem]
    @Query(sort: \Idea.modifiedAt, order: .reverse) private var ideas: [Idea]
    @State private var surpriseItem: SavedItem?
    @State private var launchDetailItem: SavedItem?
    @State private var launchDetailIdea: Idea?
    @State private var launchEditItem: SavedItem?

    let onSettings: () -> Void
    let onAdd: () -> Void

    private var resurfaced: SavedItem? {
        guard let candidate = ResurfacingEngine.pick(from: items) else { return nil }
        let reference = candidate.lastViewedAt ?? candidate.createdAt
        // Only worth a section if it has genuinely been out of sight.
        guard Date.now.timeIntervalSince(reference) > 86_400 * 14 else { return nil }
        return candidate
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MaybeMetrics.sectionSpacing) {
                header

                if items.isEmpty {
                    EmptyLibraryView(
                        symbol: "plus",
                        title: "Nothing saved yet.",
                        actionTitle: "Save your first thing",
                        action: onAdd
                    )
                } else {
                    recentSection
                    if !ideas.isEmpty { ideasSection }
                    if let resurfaced { againSection(resurfaced) }
                }
            }
            .padding(.horizontal, MaybeMetrics.pageInset)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .background(CreamCanvas())
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(item: $surpriseItem) { item in
            SurpriseView(initialItem: item)
        }
        .fullScreenCover(item: $launchDetailItem) { item in
            NavigationStack {
                ItemDetailView(item: item)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { launchDetailItem = nil }
                        }
                    }
            }
        }
        .fullScreenCover(item: $launchDetailIdea) { idea in
            NavigationStack {
                IdeaDetailView(idea: idea)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { launchDetailIdea = nil }
                        }
                    }
            }
        }
        .sheet(item: $launchEditItem) { item in
            EditItemSheet(item: item)
                .presentationDetents([.large])
        }
        .onChange(of: items.count, initial: true) { _, _ in
            openLaunchRouteIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            MaybeMark(size: 40)
            MaybeWordmark(size: 28)
            Spacer(minLength: 0)
            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(RoundKeycapButtonStyle(color: Color.white.opacity(0.75), size: 42))
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings-button")
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Recent", count: items.count)
            MasonryGrid(items: Array(items.prefix(8))) { $0.previewAspect } content: { item in
                NavigationLink {
                    ItemDetailView(item: item)
                } label: {
                    ItemTile(item: item)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private var ideasSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Ideas", count: ideas.count)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: MaybeMetrics.gutter) {
                    ForEach(ideas.prefix(6)) { idea in
                        NavigationLink {
                            IdeaDetailView(idea: idea)
                        } label: {
                            IdeaCard(idea: idea, compact: true)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.bottom, 4)
            }
            .contentMargins(.horizontal, 0, for: .scrollContent)
        }
    }

    private func againSection(_ item: SavedItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Again", actionTitle: "Surprise me") {
                surpriseItem = items.randomElement()
            }

            NavigationLink {
                ItemDetailView(item: item)
            } label: {
                HStack(spacing: 14) {
                    ItemPreview(item: item, size: .thumbnail)
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(MaybePalette.hairline, lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(MaybePalette.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("Saved \(item.createdAt.formatted(.relative(presentation: .named)))")
                            .font(.maybeMeta)
                            .foregroundStyle(MaybePalette.inkSoft)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(MaybePalette.inkFaint)
                }
                .padding(12)
                .maybePanel()
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("again-card")
        }
    }

    private func openLaunchRouteIfNeeded() {
        guard !items.isEmpty else { return }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--show-surprise"), surpriseItem == nil {
            surpriseItem = ResurfacingEngine.pick(from: items)
        } else if arguments.contains("--show-detail"), launchDetailItem == nil {
            launchDetailItem = items.first { $0.imageCount > 1 } ?? items.first
        } else if arguments.contains("--show-idea-detail"), launchDetailIdea == nil {
            launchDetailIdea = ideas.first
        } else if arguments.contains("--show-edit"), launchEditItem == nil {
            launchEditItem = items.first { $0.imageCount > 1 } ?? items.first
        }
    }
}

// MARK: - Inbox

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedItem.createdAt, order: .reverse) private var allItems: [SavedItem]
    @State private var filter: InboxFilter = .all
    @State private var editingItem: SavedItem?
    @State private var ideaItem: SavedItem?
    @State private var deleteCandidate: SavedItem?
    @State private var errorMessage: String?

    let onAdd: () -> Void

    private var inboxItems: [SavedItem] { allItems.filter(\.isInbox) }

    private var items: [SavedItem] {
        inboxItems.filter(filter.matches)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenTitle(title: "Inbox") {
                    HStack(spacing: 8) {
                        if !inboxItems.isEmpty {
                            Text("\(inboxItems.count)")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(MaybePalette.ink)
                                .frame(minWidth: 34, minHeight: 34)
                                .background { KeycapSurface(color: MaybePalette.blue, cornerRadius: 12, depth: 2) }
                                .accessibilityLabel("\(inboxItems.count) new")
                        }
                        Button(action: reviewAll) {
                            Image(systemName: "checkmark")
                        }
                        .buttonStyle(RoundKeycapButtonStyle(color: Color.white.opacity(0.75), size: 42))
                        .disabled(inboxItems.isEmpty)
                        .accessibilityLabel("Mark everything reviewed")
                    }
                }

                if !inboxItems.isEmpty {
                    filterRow
                }

                if items.isEmpty {
                    EmptyLibraryView(
                        symbol: inboxItems.isEmpty ? "tray" : "line.3.horizontal.decrease",
                        title: inboxItems.isEmpty ? "Inbox is clear." : "Nothing matches that filter.",
                        actionTitle: inboxItems.isEmpty ? "Save something" : nil,
                        action: inboxItems.isEmpty ? onAdd : nil
                    )
                } else {
                    MasonryGrid(items: items) { $0.previewAspect } content: { item in
                        NavigationLink {
                            ItemDetailView(item: item)
                        } label: {
                            ItemTile(item: item)
                        }
                        .buttonStyle(PressableStyle())
                        .contextMenu {
                            Button { review(item) } label: {
                                Label("Mark reviewed", systemImage: "checkmark.circle")
                            }
                            Button { ideaItem = item } label: {
                                Label("Add to idea", systemImage: "lightbulb.fill")
                            }
                            Button { editingItem = item } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button {
                                toggleFavorite(item)
                            } label: {
                                Label(
                                    item.isFavorite ? "Remove favourite" : "Favourite",
                                    systemImage: item.isFavorite ? "heart.slash" : "heart"
                                )
                            }
                            Divider()
                            Button(role: .destructive) { deleteCandidate = item } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, MaybeMetrics.pageInset)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(CreamCanvas())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editingItem) { item in
            EditItemSheet(item: item)
                .presentationDetents([.large])
        }
        .sheet(item: $ideaItem) { item in
            AddToIdeaSheet(item: item)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Delete this Maybe?", isPresented: deleteBinding, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text("Its local media is removed too.")
        }
        .alert("Couldn’t update Inbox", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var filterRow: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(InboxFilter.allCases) { option in
                Button {
                    filter = option
                } label: {
                    TagChip(name: option.title, color: option.color, selected: filter == option)
                }
                .buttonStyle(PressableStyle(scale: 0.95))
                .accessibilityIdentifier("filter-\(option.id)")
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func review(_ item: SavedItem) {
        do {
            try LibraryMutationService.markReviewed(item, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleFavorite(_ item: SavedItem) {
        item.isFavorite.toggle()
        item.modifiedAt = .now
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reviewAll() {
        do {
            for item in allItems where item.isInbox {
                item.isInbox = false
                item.modifiedAt = .now
            }
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelected() {
        guard let item = deleteCandidate else { return }
        do {
            try LibraryMutationService.delete(item, in: modelContext)
            deleteCandidate = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum InboxFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case photo
    case link
    case note
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .favorites: "Favourites"
        case .photo: "Photos"
        case .link: "Links"
        case .note: "Notes"
        case .file: "Files"
        }
    }

    var color: Color {
        switch self {
        case .all: MaybePalette.yellow
        case .favorites: MaybePalette.coral
        case .photo: MaybePalette.blue
        case .link: MaybePalette.green
        case .note: MaybePalette.yellow
        case .file: MaybePalette.purple
        }
    }

    func matches(_ item: SavedItem) -> Bool {
        switch self {
        case .all: true
        case .favorites: item.isFavorite
        case .photo: item.kind == .photo
        case .link: item.kind == .link
        case .note: item.kind == .note
        case .file: item.kind == .file
        }
    }
}

// MARK: - Ideas

struct IdeasView: View {
    @Query(sort: \Idea.modifiedAt, order: .reverse) private var ideas: [Idea]
    let onAdd: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenTitle(title: "Ideas") {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(RoundKeycapButtonStyle(color: MaybePalette.green, size: 44))
                    .accessibilityLabel("New idea")
                    .accessibilityIdentifier("new-idea-button")
                }

                if ideas.isEmpty {
                    EmptyLibraryView(
                        symbol: "lightbulb",
                        title: "An idea is a few saved things,\npointed at something you want to make.",
                        actionTitle: "Start an idea",
                        action: onAdd
                    )
                } else {
                    ForEach(ideas) { idea in
                        NavigationLink {
                            IdeaDetailView(idea: idea)
                        } label: {
                            IdeaCard(idea: idea)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .padding(.horizontal, MaybeMetrics.pageInset)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(CreamCanvas())
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Search

struct LibrarySearchView: View {
    @Query(sort: \SavedItem.createdAt, order: .reverse) private var items: [SavedItem]
    @Query(sort: \Idea.modifiedAt, order: .reverse) private var ideas: [Idea]
    @State private var searchText = ""
    @State private var scope: SearchScope = .everything

    private var itemResults: [SavedItem] {
        guard scope != .ideas else { return [] }
        return items.filter { item in
            guard scope.matches(item) else { return false }
            guard !searchText.isEmpty else { return true }
            return item.searchHaystack.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var ideaResults: [Idea] {
        guard scope == .everything || scope == .ideas else { return [] }
        return ideas.filter { idea in
            guard !searchText.isEmpty else { return scope == .ideas }
            let haystack = [
                idea.title,
                idea.note,
                idea.tagNames.joined(separator: " "),
                idea.items.map(\.title).joined(separator: " "),
            ].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(SearchScope.allCases) { option in
                        Button {
                            scope = option
                        } label: {
                            TagChip(name: option.title, color: option.color, selected: scope == option)
                        }
                        .buttonStyle(PressableStyle(scale: 0.95))
                        .accessibilityIdentifier("scope-\(option.id)")
                    }
                }

                if itemResults.isEmpty && ideaResults.isEmpty {
                    EmptyLibraryView(
                        symbol: "magnifyingglass",
                        title: searchText.isEmpty ? "Search titles, thoughts, tags, sources." : "Nothing matches “\(searchText)”."
                    )
                } else {
                    if !ideaResults.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Ideas", count: ideaResults.count)
                            ForEach(ideaResults) { idea in
                                NavigationLink {
                                    IdeaDetailView(idea: idea)
                                } label: {
                                    ideaRow(idea)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }

                    if !itemResults.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Things", count: itemResults.count)
                            ForEach(itemResults) { item in
                                NavigationLink {
                                    ItemDetailView(item: item)
                                } label: {
                                    ItemRow(item: item)
                                        .padding(10)
                                        .maybePanel(cornerRadius: 20)
                                }
                                .buttonStyle(PressableStyle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, MaybeMetrics.pageInset)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(CreamCanvas())
        .navigationTitle("Find")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search everything you kept"
        )
    }

    private func ideaRow(_ idea: Idea) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(MaybePalette.ink)
                .frame(width: 58, height: 58)
                .background {
                    KeycapSurface(color: Color(hex: idea.accentHex).opacity(0.85), cornerRadius: 15, depth: 2)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(idea.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(MaybePalette.ink)
                    .lineLimit(1)
                Text("Inspired by \(idea.items.count)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(MaybePalette.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .maybePanel(cornerRadius: 20)
    }
}

enum SearchScope: String, CaseIterable, Identifiable {
    case everything
    case photos
    case links
    case notes
    case files
    case ideas

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everything: "Everything"
        case .photos: "Photos"
        case .links: "Links"
        case .notes: "Notes"
        case .files: "Files"
        case .ideas: "Ideas"
        }
    }

    var color: Color {
        switch self {
        case .everything: MaybePalette.yellow
        case .photos: MaybePalette.blue
        case .links: MaybePalette.green
        case .notes: MaybePalette.yellow
        case .files: MaybePalette.coral
        case .ideas: MaybePalette.purple
        }
    }

    func matches(_ item: SavedItem) -> Bool {
        switch self {
        case .everything: true
        case .photos: item.kind == .photo
        case .links: item.kind == .link
        case .notes: item.kind == .note
        case .files: item.kind == .file
        case .ideas: false
        }
    }
}

extension SavedItem {
    var searchHaystack: String {
        [
            title,
            note,
            sourceURLString ?? "",
            tagNames.joined(separator: " "),
            ideas.map(\.title).joined(separator: " "),
            media.map(\.originalFilename).joined(separator: " "),
            createdAt.formatted(date: .long, time: .omitted),
        ].joined(separator: " ")
    }
}
