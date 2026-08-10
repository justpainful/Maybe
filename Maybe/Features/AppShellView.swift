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
    @State private var selectedTab: AppTab = .home
    @State private var presentedSheet: AppSheet?

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        _presentedSheet = State(initialValue: arguments.contains("--show-add") ? .add : nil)
        _selectedTab = State(initialValue: arguments.contains("--show-inbox") ? .inbox : .home)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            CreamCanvas()

            TabView(selection: $selectedTab) {
                Tab("Home", systemImage: "house.fill", value: .home) {
                    NavigationStack {
                        HomeView {
                            presentedSheet = .settings
                        }
                    }
                }

                Tab("Inbox", systemImage: "tray.full.fill", value: .inbox) {
                    NavigationStack {
                        InboxView()
                    }
                }

                Tab("Ideas", systemImage: "lightbulb.max.fill", value: .ideas) {
                    NavigationStack {
                        IdeasView {
                            presentedSheet = .newIdea(nil)
                        }
                    }
                }

                Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
                    NavigationStack {
                        LibrarySearchView()
                    }
                }
            }
            .tint(MaybePalette.ink)

            Button {
                presentedSheet = .add
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(RoundKeycapButtonStyle(color: MaybePalette.purple, size: 62))
            .padding(.bottom, 24)
            .accessibilityLabel("Add to Maybe")
            .accessibilityIdentifier("add-button")
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .add:
                AddMaybeSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            case .newIdea(let item):
                NewIdeaSheet(preselectedItem: item)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            case .settings:
                SettingsView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}
