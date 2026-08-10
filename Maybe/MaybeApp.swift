import SwiftData
import SwiftUI

@main
struct MaybeApp: App {
    private let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            SavedItem.self,
            Idea.self,
            MediaAttachment.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unable to create Maybe's local library: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .preferredColorScheme(.light)
                .task {
                    SampleLibrarySeeder.seedIfNeeded(in: modelContainer.mainContext)
                }
        }
        .modelContainer(modelContainer)
    }
}

