import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case home
    case inbox
    case ideas
    case search

    var title: String {
        switch self {
        case .home: "Home"
        case .inbox: "Inbox"
        case .ideas: "Ideas"
        case .search: "Find"
        }
    }

    var symbol: String {
        switch self {
        case .home: "square.grid.2x2"
        case .inbox: "tray"
        case .ideas: "lightbulb"
        case .search: "magnifyingglass"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .home: "square.grid.2x2.fill"
        case .inbox: "tray.fill"
        case .ideas: "lightbulb.fill"
        case .search: "magnifyingglass"
        }
    }

    var accent: Color {
        switch self {
        case .home: MaybePalette.coral
        case .inbox: MaybePalette.blue
        case .ideas: MaybePalette.yellow
        case .search: MaybePalette.green
        }
    }
}

enum AppSheet: Identifiable {
    case add
    case newIdea(SavedItem?)
    case settings

    var id: String {
        switch self {
        case .add: "add"
        case .newIdea: "new-idea"
        case .settings: "settings"
        }
    }
}

struct AppShellView: View {
    let startupIssue: String?
    @State private var selectedTab: AppTab = .home
    @State private var presentedSheet: AppSheet?
    @State private var isShowingStartupIssue = false

    init(startupIssue: String? = nil) {
        self.startupIssue = startupIssue
        let arguments = ProcessInfo.processInfo.arguments
        let initialSheet: AppSheet? = if arguments.contains("--show-add") {
            .add
        } else if arguments.contains("--show-settings") {
            .settings
        } else {
            nil
        }
        let initialTab: AppTab = if arguments.contains("--show-inbox") {
            .inbox
        } else if arguments.contains("--show-ideas") {
            .ideas
        } else if arguments.contains("--show-search") {
            .search
        } else {
            .home
        }
        _presentedSheet = State(initialValue: initialSheet)
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack {
            CreamCanvas()

            switch selectedTab {
            case .home:
                NavigationStack {
                    HomeView(
                        onSettings: { presentedSheet = .settings },
                        onAdd: { presentedSheet = .add }
                    )
                }
            case .inbox:
                NavigationStack {
                    InboxView(onAdd: { presentedSheet = .add })
                }
            case .ideas:
                NavigationStack {
                    IdeasView { presentedSheet = .newIdea(nil) }
                }
            case .search:
                NavigationStack {
                    LibrarySearchView()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MaybeTabBar(selection: $selectedTab) {
                presentedSheet = .add
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .add:
                AddMaybeSheet()
                    .presentationDetents([.large])
            case .newIdea(let item):
                NewIdeaSheet(preselectedItem: item)
                    .presentationDetents([.large])
            case .settings:
                SettingsView()
                    .presentationDetents([.large])
            }
        }
        .task {
            isShowingStartupIssue = startupIssue != nil
            if ProcessInfo.processInfo.arguments.contains("--show-new-idea") {
                try? await Task.sleep(for: .milliseconds(350))
                presentedSheet = .newIdea(nil)
            }
        }
        .alert("Local library unavailable", isPresented: $isShowingStartupIssue) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(startupIssue ?? "Please relaunch Maybe.")
        }
    }
}

private struct MaybeTabBar: View {
    @Binding var selection: AppTab
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            tabButton(.home)
            tabButton(.inbox)

            Button(action: onAdd) {
                Image(systemName: "plus")
            }
            .buttonStyle(RoundKeycapButtonStyle(color: MaybePalette.purple, size: 50, depth: 4))
            .padding(.horizontal, 4)
            .accessibilityLabel("Add to Maybe")
            .accessibilityIdentifier("add-button")

            tabButton(.ideas)
            tabButton(.search)
        }
        .padding(6)
        .background(Color.white.opacity(0.22), in: Capsule())
        .glassEffect(.regular, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
        .shadow(color: MaybePalette.ink.opacity(0.14), radius: 6, y: 4)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            withAnimation(.snappy(duration: 0.22)) { selection = tab }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: isSelected ? tab.selectedSymbol : tab.symbol)
                    .font(.system(size: 17, weight: isSelected ? .bold : .medium))
                    .symbolRenderingMode(.monochrome)
                Text(tab.title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(MaybePalette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                if isSelected {
                    KeycapSurface(color: tab.accent, cornerRadius: 15, depth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityIdentifier("tab-\(tab.title.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
