import Foundation
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
}
