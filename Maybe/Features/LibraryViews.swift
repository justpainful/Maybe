import SwiftData
import SwiftUI

struct HomeView: View {
    @Query(sort: \SavedItem.createdAt, order: .reverse) private var items: [SavedItem]
    @Query(sort: \Idea.modifiedAt, order: .reverse) private var ideas: [Idea]
    @State private var surpriseItem: SavedItem?
    @State private var launchDetailItem: SavedItem?

    let onSettings: () -> Void
    let onAdd: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MaybeMetrics.sectionSpacing) {
                MaybeHeader(trailingAction: onSettings)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Things that caught you.")
                        .font(.maybeRounded(28, weight: .black))
                    Text("Keep them close. Turn them into ideas.")
                        .font(.subheadline)
                        .foregroundStyle(MaybePalette.ink.opacity(0.58))
                }

                if items.isEmpty && ideas.isEmpty {
                    firstRunSection
                } else {
                    recentlySection
                    againSection
                    ideasSection
                    surpriseSection
                }
            }
            .padding(.horizontal, MaybeMetrics.pageInset)
            .padding(.top, 10)
            .padding(.bottom, 28)
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
        .onChange(of: items.count, initial: true) { _, _ in
            openLaunchRouteIfNeeded()
        }
    }

    private var firstRunSection: some View {
        VStack(spacing: 20) {
            EmptyLibraryView(
                symbol: "sparkles.rectangle.stack",
                title: "Catch your first Maybe",
                message: "Save a photo, link, note, or file. Everything stays on this device."
            )
            Button(action: onAdd) {
                Label("Add to Maybe", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: 20))
            .tint(MaybePalette.purple)
            .foregroundStyle(MaybePalette.ink)
        }
    }

    private func openLaunchRouteIfNeeded() {
        guard !items.isEmpty else { return }
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--show-surprise"), surpriseItem == nil {
            surpriseItem = ResurfacingEngine.pick(from: items)
        } else if arguments.contains("--show-detail"), launchDetailItem == nil {
            launchDetailItem = items.first
        }
    }

    private var recentlySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            MaybeSectionHeader(title: "Recently", subtitle: "Your newest saves")

            if items.isEmpty {
                EmptyLibraryView(
                    symbol: "sparkles.rectangle.stack",
                    title: "Save your first thing",
                    message: "A photo, link, note, or file can become a Maybe."
                )
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items.prefix(2)) { item in
                        NavigationLink {
                            ItemDetailView(item: item)
                        } label: {
                            SavedCard(item: item, width: nil)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var ideasSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            MaybeSectionHeader(title: "Ideas", subtitle: "What your saves are becoming")

            if ideas.isEmpty {
                EmptyLibraryView(
                    symbol: "lightbulb.max.fill",
                    title: "Ideas start with a Maybe",
                    message: "Connect saved things to something you want to make."
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(ideas.prefix(5)) { idea in
                            NavigationLink {
                                IdeaDetailView(idea: idea)
                            } label: {
                                IdeaCard(idea: idea, compact: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .scrollEdgeEffectHidden(true, for: .all)
                .scrollClipDisabled()
            }
        }
    }

    @ViewBuilder
    private var againSection: some View {
        if let resurfaced = ResurfacingEngine.pick(from: items) {
            VStack(alignment: .leading, spacing: 14) {
                MaybeSectionHeader(title: "Again", subtitle: "You saved this a while ago")
                NavigationLink {
                    ItemDetailView(item: resurfaced)
                } label: {
                    HStack(spacing: 16) {
                        InspirationThumbnail(item: resurfaced)
                            .frame(width: 132, height: 142)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                        VStack(alignment: .leading, spacing: 9) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.title2)
                            Text(resurfaced.title)
                                .font(.system(.title3, design: .rounded, weight: .bold))
                                .multilineTextAlignment(.leading)
                            Text(resurfaced.note)
                                .font(.caption)
                                .foregroundStyle(MaybePalette.ink.opacity(0.58))
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Label("Open again", systemImage: "arrow.up.right")
                                .font(.system(.caption, design: .rounded, weight: .bold))
                        }
                        .foregroundStyle(MaybePalette.ink)
                        .padding(.vertical, 8)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 29, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 29, style: .continuous).stroke(Color.white.opacity(0.8), lineWidth: 1))
                    .shadow(color: MaybePalette.ink.opacity(0.1), radius: 8, y: 5)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var surpriseSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            MaybeSectionHeader(title: "Maybe?", subtitle: "Rediscover one thing at a time")
            Button {
                surpriseItem = items.randomElement()
            } label: {
                Label("Surprise me", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(KeycapButtonStyle(color: MaybePalette.yellow, cornerRadius: 22))
            .disabled(items.isEmpty)
            .accessibilityIdentifier("surprise-button")
        }
    }
}

struct InboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedItem.createdAt, order: .reverse) private var allItems: [SavedItem]
    @State private var selectedKind: MaybeKind?
    @State private var favoritesOnly = false
    @State private var editingItem: SavedItem?
    @State private var ideaItem: SavedItem?
    @State private var deleteCandidate: SavedItem?
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    private var items: [SavedItem] {
        allItems.filter { item in
            item.isInbox
                && (selectedKind == nil || item.kind == selectedKind)
                && (!favoritesOnly || item.isFavorite)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Inbox")
                            .font(.maybeRounded(32, weight: .black))
                        Text("\(allItems.filter(\.isInbox).count) new things")
                            .foregroundStyle(MaybePalette.ink.opacity(0.56))
                    }
                    Spacer()
                    Button(action: reviewAll) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 19, weight: .bold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.roundedRectangle(radius: 15))
                    .tint(MaybePalette.blue.opacity(0.72))
                    .foregroundStyle(MaybePalette.ink)
                    .disabled(allItems.allSatisfy { !$0.isInbox })
                    .accessibilityLabel("Mark all Inbox items reviewed")
                }

                filters

                if items.isEmpty {
                    EmptyLibraryView(
                        symbol: "tray",
                        title: "Nothing here yet",
                        message: "Quick saves land here. You never have to clean it up."
                    )
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(items) { item in
                            ZStack(alignment: .topTrailing) {
                                NavigationLink {
                                    ItemDetailView(item: item)
                                } label: {
                                    SavedCard(item: item, width: nil)
                                }
                                .buttonStyle(.plain)

                                Menu {
                                    Button { review(item) } label: {
                                        Label("Mark reviewed", systemImage: "checkmark.circle")
                                    }
                                    Button { ideaItem = item } label: {
                                        Label("Add to idea", systemImage: "lightbulb.max.fill")
                                    }
                                    Button { editingItem = item } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button {
                                        item.isFavorite.toggle()
                                        item.modifiedAt = .now
                                        try? modelContext.save()
                                    } label: {
                                        Label(item.isFavorite ? "Remove favorite" : "Favorite", systemImage: item.isFavorite ? "heart.slash" : "heart")
                                    }
                                    Divider()
                                    Button(role: .destructive) { deleteCandidate = item } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 15, weight: .bold))
                                        .frame(width: 40, height: 40)
                                }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.circle)
                                .tint(MaybePalette.glassWhite.opacity(0.72))
                                .foregroundStyle(MaybePalette.ink)
                                .padding(12)
                                .accessibilityLabel("Actions for \(item.title)")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, MaybeMetrics.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 28)
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
            Text("Its local media will also be removed.")
        }
        .alert("Couldn’t update Inbox", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                Button {
                    selectedKind = nil
                    favoritesOnly = false
                } label: {
                    FilterKeycap(name: "All", color: MaybePalette.yellow, selected: selectedKind == nil && !favoritesOnly)
                }
                Button {
                    favoritesOnly.toggle()
                } label: {
                    FilterKeycap(name: "Favorites", color: MaybePalette.coral, selected: favoritesOnly)
                }
                ForEach(MaybeKind.allCases) { kind in
                    Button {
                        selectedKind = selectedKind == kind ? nil : kind
                    } label: {
                        FilterKeycap(name: kind.title, color: Color(hex: accent(for: kind)), selected: selectedKind == kind)
                    }
                }
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .scrollEdgeEffectHidden(true, for: .all)
        .scrollClipDisabled()
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

    private func accent(for kind: MaybeKind) -> String {
        switch kind {
        case .photo: "70AEFF"
        case .link: "87E56D"
        case .note: "FFD83D"
        case .file: "7957FF"
        }
    }
}

struct IdeasView: View {
    @Query(sort: \Idea.modifiedAt, order: .reverse) private var ideas: [Idea]
    let onAdd: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ideas")
                            .font(.maybeRounded(32, weight: .black))
                        Text("Saved things, put to work.")
                            .foregroundStyle(MaybePalette.ink.opacity(0.56))
                    }
                    Spacer()
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(RoundKeycapButtonStyle(color: MaybePalette.green, size: 50))
                    .accessibilityLabel("New idea")
                }

                if ideas.isEmpty {
                    EmptyLibraryView(
                        symbol: "lightbulb.max",
                        title: "Make an idea",
                        message: "Connect the things that inspired it."
                    )
                } else {
                    ForEach(ideas) { idea in
                        NavigationLink {
                            IdeaDetailView(idea: idea)
                        } label: {
                            IdeaCard(idea: idea)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, MaybeMetrics.pageInset)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(CreamCanvas())
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct FilterKeycap: View {
    let name: String
    let color: Color
    let selected: Bool

    var body: some View {
        Text(name)
            .font(.system(.caption, design: .rounded, weight: .bold))
            .foregroundStyle(MaybePalette.ink)
            .padding(.horizontal, 15)
            .frame(minHeight: 44)
            .background(selected ? color.opacity(0.46) : Color.white.opacity(0.14), in: Capsule())
            .glassEffect(.regular.tint(color.opacity(selected ? 0.28 : 0.08)).interactive(), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.75), lineWidth: 1))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct LibrarySearchView: View {
    @Query(sort: \SavedItem.createdAt, order: .reverse) private var items: [SavedItem]
    @Query(sort: \Idea.modifiedAt, order: .reverse) private var ideas: [Idea]
    @State private var searchText = ""
    @State private var selectedKind: MaybeKind?
    @State private var showsIdeas = false

    private var results: [SavedItem] {
        guard !showsIdeas else { return [] }
        return items.filter { item in
            let matchesKind = selectedKind == nil || item.kind == selectedKind
            guard matchesKind else { return false }
            guard !searchText.isEmpty else { return true }
            let haystack = [
                item.title,
                item.note,
                item.sourceURLString ?? "",
                item.tagNames.joined(separator: " "),
                item.ideas.map(\.title).joined(separator: " "),
                item.media.map(\.originalFilename).joined(separator: " "),
                item.createdAt.formatted(date: .long, time: .omitted),
            ].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var ideaResults: [Idea] {
        guard showsIdeas else { return [] }
        return ideas.filter { idea in
            guard !searchText.isEmpty else { return true }
            let haystack = [
                idea.title,
                idea.note,
                idea.tagNames.joined(separator: " "),
                idea.items.map(\.title).joined(separator: " "),
                idea.modifiedAt.formatted(date: .long, time: .omitted),
            ].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        Button {
                            selectedKind = nil
                            showsIdeas = false
                        } label: {
                            FilterKeycap(name: "All", color: MaybePalette.yellow, selected: selectedKind == nil && !showsIdeas)
                        }
                        ForEach(MaybeKind.allCases) { kind in
                            Button {
                                selectedKind = selectedKind == kind ? nil : kind
                                showsIdeas = false
                            } label: {
                                FilterKeycap(name: kind.title, color: accent(for: kind), selected: selectedKind == kind)
                            }
                        }
                        Button {
                            selectedKind = nil
                            showsIdeas = true
                        } label: {
                            FilterKeycap(name: "Ideas", color: MaybePalette.purple, selected: showsIdeas)
                        }
                    }
                    .padding(.vertical, 5)
                }
                .scrollEdgeEffectHidden(true, for: .all)
                .scrollClipDisabled()
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: MaybeMetrics.pageInset, bottom: 8, trailing: MaybeMetrics.pageInset))
            }

            if results.isEmpty && ideaResults.isEmpty {
                EmptyLibraryView(
                    symbol: "magnifyingglass",
                    title: "No match",
                    message: "Try a title, thought, source, tag, or idea name."
                )
                .listRowBackground(Color.clear)
            } else if showsIdeas {
                Section("\(ideaResults.count) ideas") {
                    ForEach(ideaResults) { idea in
                        NavigationLink {
                            IdeaDetailView(idea: idea)
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: "lightbulb.max.fill")
                                    .font(.title3)
                                    .foregroundStyle(MaybePalette.ink)
                                    .frame(width: 54, height: 50)
                                    .background(Color(hex: idea.accentHex).opacity(0.55), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(idea.title)
                                        .font(.system(.headline, design: .rounded, weight: .bold))
                                    Text("Inspired by \(idea.items.count) things")
                                        .font(.caption)
                                        .foregroundStyle(MaybePalette.ink.opacity(0.56))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.35))
                }
            } else {
                Section("\(results.count) results") {
                    ForEach(results) { item in
                        NavigationLink {
                            ItemDetailView(item: item)
                        } label: {
                            HStack(spacing: 13) {
                                InspirationThumbnail(item: item)
                                    .frame(width: 70, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.system(.headline, design: .rounded, weight: .bold))
                                    Text(item.note.isEmpty ? item.kind.title : item.note)
                                        .font(.caption)
                                        .foregroundStyle(MaybePalette.ink.opacity(0.56))
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.35))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(CreamCanvas())
        .navigationTitle("Find anything")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search your Maybes")
    }

    private func accent(for kind: MaybeKind) -> Color {
        switch kind {
        case .photo: MaybePalette.blue
        case .link: MaybePalette.green
        case .note: MaybePalette.yellow
        case .file: MaybePalette.purple
        }
    }
}
