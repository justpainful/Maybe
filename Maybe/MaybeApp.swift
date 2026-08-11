import SwiftData
import SwiftUI

@main
struct MaybeApp: App {
    private let modelContainer: ModelContainer
    private let startupIssue: String?

    init() {
        let schema = Schema(versionedSchema: MaybeSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            modelContainer = try ModelContainer(
                for: MaybeSchemaV1.self,
                migrationPlan: MaybeMigrationPlan.self,
                configurations: [configuration]
            )
            startupIssue = nil
        } catch {
            modelContainer = try! ModelContainer(
                for: MaybeSchemaV1.self,
                migrationPlan: MaybeMigrationPlan.self,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
            startupIssue = "Maybe couldn’t open the local library. This session is temporary; export or change nothing until the library is repaired. \(error.localizedDescription)"
        }
    }

    var body: some Scene {
        WindowGroup {
            AppShellView(startupIssue: startupIssue)
                .preferredColorScheme(.light)
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--use-sample-data") {
                        SampleLibrarySeeder.seedIfNeeded(in: modelContainer.mainContext)
                    }
                    _ = ShareInboxImporter.importPending(into: modelContainer.mainContext)
                    let ideas = (try? modelContainer.mainContext.fetch(FetchDescriptor<Idea>())) ?? []
                    MaybeSharedContainer.publishIdeaTitles(ideas.map(\.title))
                }
        }
        .modelContainer(modelContainer)
    }
}
