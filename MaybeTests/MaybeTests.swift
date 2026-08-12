import Foundation
import SwiftData
import Testing
@testable import Maybe

struct MaybeTests {
    @Test("Brand colors parse their RGB channels")
    func brandColorHexValuesAreStable() {
        #expect(MaybePalette.accentHexes == ["7957FF", "FFD83D", "70AEFF", "87E56D", "FF8066"])
    }

    @Test("Duplicate hashes are deterministic")
    func duplicateHashIsDeterministic() {
        let data = Data("maybe-local-file".utf8)
        #expect(LocalMediaStore.hash(data) == LocalMediaStore.hash(data))
        #expect(LocalMediaStore.hash(data) != LocalMediaStore.hash(Data("another-file".utf8)))
    }

    @Test("Share records survive local serialization")
    func shareRecordRoundTrip() throws {
        let record = SharedCaptureRecord(
            kindRawValue: "link",
            title: "Reference",
            thought: "The floating controls",
            sourceURLString: "https://example.com",
            ideaTitle: "Maybe app UI"
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(SharedCaptureRecord.self, from: data)

        #expect(decoded.id == record.id)
        #expect(decoded.ideaTitle == "Maybe app UI")
    }

    @Test("An unseen favorite resurfaces before a fresh item")
    func resurfacingPrefersOldUsefulThings() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let fresh = SavedItem(
            kind: .note,
            title: "Fresh",
            createdAt: now.addingTimeInterval(-3_600),
            isInbox: true
        )
        let olderFavorite = SavedItem(
            kind: .photo,
            title: "Older favorite",
            createdAt: now.addingTimeInterval(-86_400 * 60),
            lastViewedAt: now.addingTimeInterval(-86_400 * 50),
            isFavorite: true,
            isInbox: false
        )

        #expect(ResurfacingEngine.score(olderFavorite, now: now) > ResurfacingEngine.score(fresh, now: now))
    }

    @Test("Inbox items can be marked reviewed")
    @MainActor
    func inboxReviewPersists() throws {
        let schema = Schema(versionedSchema: MaybeSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: MaybeMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let item = SavedItem(kind: .note, title: "Review me", isInbox: true)
        container.mainContext.insert(item)

        try LibraryMutationService.markReviewed(item, in: container.mainContext)

        #expect(item.isInbox == false)
        #expect(item.modifiedAt <= .now)
    }

    @Test("Deleting an idea keeps its saved items")
    @MainActor
    func deletingIdeaPreservesItems() throws {
        let schema = Schema(versionedSchema: MaybeSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: MaybeMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let item = SavedItem(kind: .photo, title: "Reference")
        let idea = Idea(title: "Draft", items: [item])
        container.mainContext.insert(item)
        container.mainContext.insert(idea)
        try container.mainContext.save()

        try LibraryMutationService.delete(idea, in: container.mainContext)

        #expect(try container.mainContext.fetch(FetchDescriptor<Idea>()).isEmpty)
        #expect(try container.mainContext.fetch(FetchDescriptor<SavedItem>()).count == 1)
    }

    @Test("One Maybe holds several photos, in order, at their real sizes")
    @MainActor
    func severalPhotosAttachToOneItem() throws {
        let schema = Schema(versionedSchema: MaybeSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: MaybeMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let item = SavedItem(kind: .photo, title: "A few photos")
        container.mainContext.insert(item)

        let sizes = [(300, 400), (400, 300), (250, 250)]
        let payloads = sizes.enumerated().compactMap { index, size in
            SamplePhotoFactory.jpeg(width: size.0, height: size.1, seed: index)
        }
        #expect(payloads.count == 3)

        try LibraryMutationService.addPhotos(payloads, to: item, in: container.mainContext)

        #expect(item.imageCount == 3)
        #expect(item.images.map(\.width) == [300, 400, 250])
        #expect(item.images.map(\.height) == [400, 300, 250])
        #expect(item.previewAspect == MediaAspect.ratio(width: 300, height: 400))

        // The same photo twice is still one photo.
        try LibraryMutationService.addPhotos([payloads[0]], to: item, in: container.mainContext)
        #expect(item.imageCount == 3)

        let removed = try #require(item.images.first)
        try LibraryMutationService.removeMedia(removed, from: item, in: container.mainContext)
        #expect(item.imageCount == 2)
        #expect(item.images.map(\.width) == [400, 250])
    }

    @Test("A tile never gets a shape extreme enough to break the grid")
    func previewAspectIsClamped() {
        #expect(MediaAspect.ratio(width: 100, height: 1_000) == MediaAspect.minimum)
        #expect(MediaAspect.ratio(width: 1_000, height: 100) == MediaAspect.maximum)
        #expect(MediaAspect.ratio(width: 0, height: 0) == 1)
        #expect(SavedItem(kind: .note, title: "No media").previewAspect == 0.88)
    }

    @Test("Photo filenames sort into the order they were added")
    func photoFilenamesSortByAdditionOrder() {
        let earlier = Date(timeIntervalSince1970: 1_000_000)
        let later = earlier.addingTimeInterval(60)
        let first = LocalMediaStore.photoFilename(index: 0, date: earlier)
        let second = LocalMediaStore.photoFilename(index: 1, date: earlier)
        let third = LocalMediaStore.photoFilename(index: 2, date: later)

        #expect(first < second)
        #expect(second < third)
    }

    @Test("An exported library carries a page any browser can open")
    @MainActor
    func exportedPackageCarriesAPage() throws {
        let schema = Schema(versionedSchema: MaybeSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: MaybeMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let item = SavedItem(
            kind: .photo,
            title: "Glass buttons",
            note: "The way the light sits on the top edge",
            tagNames: ["UI"]
        )
        let idea = Idea(title: "Maybe app UI", items: [item])
        container.mainContext.insert(item)
        container.mainContext.insert(idea)
        try container.mainContext.save()

        let package = try LibraryArchiveService.exportPackage(items: [item], ideas: [idea])
        let data = try #require(package.fileWrappers?[ExportPage.filename]?.regularFileContents)
        let html = try #require(String(data: data, encoding: .utf8))

        #expect(html.contains("The way the light sits on the top edge"))
        #expect(html.contains("Maybe app UI"))
        // Browsers refuse to fetch sibling files from file://, so the library
        // has to travel inside the page, and nothing may come off the network.
        #expect(!html.contains("/*__MAYBE_LIBRARY__*/"))
        #expect(!html.contains("<script src"))
        #expect(!html.contains("<link rel=\"stylesheet\""))
    }

    @Test("The page escapes anything that could close its own script tag")
    func exportPageEscapesClosingTags() throws {
        let item = SavedItem(kind: .note, title: "</script> and more", note: "Still fine")
        let data = try #require(
            ExportPage.render(
                items: [item],
                ideas: [],
                locations: [:],
                template: "<html><script>/*__MAYBE_LIBRARY__*/</script></html>"
            )
        )
        let html = try #require(String(data: data, encoding: .utf8))

        #expect(html.contains("<\\/script>"))
        #expect(html.components(separatedBy: "</script>").count == 2)
    }

    @Test("Library backup is a package with JSON and media folders")
    @MainActor
    func libraryPackageRoundTrip() throws {
        let schema = Schema(versionedSchema: MaybeSchemaV1.self)
        let source = try ModelContainer(
            for: schema,
            migrationPlan: MaybeMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let item = SavedItem(kind: .note, title: "A useful thought", note: "Keep this")
        let idea = Idea(title: "A future project", items: [item])
        source.mainContext.insert(item)
        source.mainContext.insert(idea)
        try source.mainContext.save()

        let package = try LibraryArchiveService.exportPackage(items: [item], ideas: [idea])
        #expect(package.isDirectory)
        #expect(package.fileWrappers?["library.json"] != nil)
        #expect(package.fileWrappers?["media"]?.isDirectory == true)
        #expect(package.fileWrappers?["thumbnails"]?.isDirectory == true)

        let destination = try ModelContainer(
            for: schema,
            migrationPlan: MaybeMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let imported = try LibraryArchiveService.importPackage(wrapper: package, into: destination.mainContext)

        #expect(imported == 1)
        #expect(try destination.mainContext.fetch(FetchDescriptor<SavedItem>()).first?.title == "A useful thought")
        #expect(try destination.mainContext.fetch(FetchDescriptor<Idea>()).first?.items.count == 1)
    }
}
