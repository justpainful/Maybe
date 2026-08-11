import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case home
    case inbox
    case ideas
    case search
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
        Group {
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
                    InboxView()
                }
            case .ideas:
                NavigationStack {
                    IdeasView {
                        presentedSheet = .newIdea(nil)
                    }
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
            .padding(.horizontal, 14)
            .padding(.top, 7)
            .padding(.bottom, 6)
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .add:
                AddMaybeSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .newIdea(let item):
                NewIdeaSheet(preselectedItem: item)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .settings:
                SettingsView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
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
            tabButton(.home, title: "Home", symbol: "house", selectedSymbol: "house.fill", color: MaybePalette.coral)
            tabButton(.inbox, title: "Inbox", symbol: "tray", selectedSymbol: "tray.full.fill", color: MaybePalette.blue)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .tint(MaybePalette.purple)
            .foregroundStyle(MaybePalette.ink)
            .accessibilityLabel("Add to Maybe")
            .accessibilityIdentifier("add-button")

            tabButton(.ideas, title: "Ideas", symbol: "lightbulb.max", selectedSymbol: "lightbulb.max.fill", color: MaybePalette.yellow)
            tabButton(.search, title: "Find", symbol: "magnifyingglass", selectedSymbol: "magnifyingglass", color: MaybePalette.green)
        }
        .padding(7)
        .background(Color.white.opacity(0.18), in: Capsule())
        .glassEffect(.regular, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.84), lineWidth: 1))
        .shadow(color: MaybePalette.ink.opacity(0.16), radius: 7, y: 5)
    }

    private func tabButton(
        _ tab: AppTab,
        title: String,
        symbol: String,
        selectedSymbol: String,
        color: Color
    ) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.24)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: selection == tab ? selectedSymbol : symbol)
                    .font(.system(size: 18, weight: selection == tab ? .bold : .semibold))
                    .symbolRenderingMode(.monochrome)
                Text(title)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
            }
            .foregroundStyle(MaybePalette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(selection == tab ? color.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                if selection == tab {
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(Color.white.opacity(0.75), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}
