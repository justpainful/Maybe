import SwiftData
import SwiftUI

struct HomeView: View {
    @Query(sort: \SavedItem.createdAt, order: .reverse) private var items: [SavedItem]
    @Query(sort: \Idea.modifiedAt, order: .reverse) private var ideas: [Idea]
    @State private var surpriseItem: SavedItem?

    let onSettings: () -> Void

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

                recentlySection
                ideasSection
                againSection
                surpriseSection
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
    @Query(sort: \SavedItem.createdAt, order: .reverse) private var allItems: [SavedItem]
    @State private var selectedKind: MaybeKind?
    @State private var favoritesOnly = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    private let filterColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var items: [SavedItem] {
        allItems.filter { item in
            (item.isInbox || selectedKind != nil || favoritesOnly)
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
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 19, weight: .bold))
                        .frame(width: 46, height: 44)
                        .background(MaybePalette.blue.opacity(0.82), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.white.opacity(0.8), lineWidth: 1))
                        .shadow(color: MaybePalette.ink.opacity(0.12), radius: 1, y: 3)
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
                            NavigationLink {
                                ItemDetailView(item: item)
                            } label: {
                                SavedCard(item: item, width: nil)
                            }
                            .buttonStyle(.plain)
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
    }

    private var filters: some View {
        LazyVGrid(columns: filterColumns, spacing: 9) {
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
        .buttonStyle(.plain)
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
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background((selected ? color : color.opacity(0.58)), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.white.opacity(0.82), lineWidth: 1)
                    .padding(1)
            }
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(MaybePalette.ink.opacity(selected ? 0.2 : 0.1), lineWidth: 1))
            .shadow(color: MaybePalette.ink.opacity(0.12), radius: 0.5, y: selected ? 3 : 2)
    }
}

struct LibrarySearchView: View {
    @Query(sort: \SavedItem.createdAt, order: .reverse) private var items: [SavedItem]
    @State private var searchText = ""
    @State private var selectedKind: MaybeKind?
    private let filterColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    private var results: [SavedItem] {
        items.filter { item in
            let matchesKind = selectedKind == nil || item.kind == selectedKind
            guard matchesKind else { return false }
            guard !searchText.isEmpty else { return true }
            let haystack = [
                item.title,
                item.note,
                item.sourceURLString ?? "",
                item.tagNames.joined(separator: " "),
                item.ideas.map(\.title).joined(separator: " "),
            ].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: filterColumns, spacing: 9) {
                    Button {
                        selectedKind = nil
                    } label: {
                        FilterKeycap(name: "All", color: MaybePalette.yellow, selected: selectedKind == nil)
                    }
                    ForEach(MaybeKind.allCases) { kind in
                        Button {
                            selectedKind = selectedKind == kind ? nil : kind
                        } label: {
                            FilterKeycap(name: kind.title, color: accent(for: kind), selected: selectedKind == kind)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: MaybeMetrics.pageInset, bottom: 8, trailing: MaybeMetrics.pageInset))
            }

            if results.isEmpty {
                EmptyLibraryView(
                    symbol: "magnifyingglass",
                    title: "No match",
                    message: "Try a title, thought, source, tag, or idea name."
                )
                .listRowBackground(Color.clear)
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
