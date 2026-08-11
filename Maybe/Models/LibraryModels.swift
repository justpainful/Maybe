import Foundation
import SwiftData

enum MaybeSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SavedItem.self, Idea.self, MediaAttachment.self]
    }
}

enum MaybeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MaybeSchemaV1.self]
    }

    static var stages: [MigrationStage] { [] }
}

enum MaybeKind: String, Codable, CaseIterable, Identifiable {
    case photo
    case link
    case note
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: "Photo"
        case .link: "Link"
        case .note: "Note"
        case .file: "File"
        }
    }

    var symbol: String {
        switch self {
        case .photo: "photo.on.rectangle.angled"
        case .link: "link"
        case .note: "text.quote"
        case .file: "doc.fill"
        }
    }
}

enum MediaKind: String, Codable {
    case image
    case video
    case file
}

@Model
final class SavedItem: Identifiable {
    @Attribute(.unique) var id: UUID
    var kindRawValue: String
    var title: String
    var note: String
    var createdAt: Date
    var modifiedAt: Date
    var lastViewedAt: Date?
    var sourceURLString: String?
    var isFavorite: Bool
    var isInbox: Bool
    var tagNames: [String]
    var accentHex: String
    var visualSeed: Int

    @Relationship(deleteRule: .cascade, inverse: \MediaAttachment.item)
    var media: [MediaAttachment]

    @Relationship(inverse: \Idea.items)
    var ideas: [Idea]

    init(
        id: UUID = UUID(),
        kind: MaybeKind,
        title: String,
        note: String = "",
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        lastViewedAt: Date? = nil,
        sourceURLString: String? = nil,
        isFavorite: Bool = false,
        isInbox: Bool = true,
        tagNames: [String] = [],
        accentHex: String = "7957FF",
        visualSeed: Int = 0,
        media: [MediaAttachment] = [],
        ideas: [Idea] = []
    ) {
        self.id = id
        kindRawValue = kind.rawValue
        self.title = title
        self.note = note
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.lastViewedAt = lastViewedAt
        self.sourceURLString = sourceURLString
        self.isFavorite = isFavorite
        self.isInbox = isInbox
        self.tagNames = tagNames
        self.accentHex = accentHex
        self.visualSeed = visualSeed
        self.media = media
        self.ideas = ideas
    }

    var kind: MaybeKind {
        get { MaybeKind(rawValue: kindRawValue) ?? .note }
        set { kindRawValue = newValue.rawValue }
    }
}

@Model
final class Idea: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var note: String
    var createdAt: Date
    var modifiedAt: Date
    var coverItemID: UUID?
    var tagNames: [String]
    var accentHex: String

    @Relationship
    var items: [SavedItem]

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        coverItemID: UUID? = nil,
        tagNames: [String] = [],
        accentHex: String = "FFD83D",
        items: [SavedItem] = []
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.coverItemID = coverItemID
        self.tagNames = tagNames
        self.accentHex = accentHex
        self.items = items
    }
}

@Model
final class MediaAttachment: Identifiable {
    @Attribute(.unique) var id: UUID
    var typeRawValue: String
    var localPath: String
    var thumbnailPath: String?
    var width: Double
    var height: Double
    var originalFilename: String
    var sha256: String
    var item: SavedItem?

    init(
        id: UUID = UUID(),
        type: MediaKind,
        localPath: String,
        thumbnailPath: String? = nil,
        width: Double = 0,
        height: Double = 0,
        originalFilename: String,
        sha256: String,
        item: SavedItem? = nil
    ) {
        self.id = id
        typeRawValue = type.rawValue
        self.localPath = localPath
        self.thumbnailPath = thumbnailPath
        self.width = width
        self.height = height
        self.originalFilename = originalFilename
        self.sha256 = sha256
        self.item = item
    }

    var type: MediaKind {
        get { MediaKind(rawValue: typeRawValue) ?? .file }
        set { typeRawValue = newValue.rawValue }
    }
}

enum SampleLibrarySeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        var descriptor = FetchDescriptor<SavedItem>()
        descriptor.fetchLimit = 1
        guard (try? context.fetch(descriptor))?.isEmpty == true else { return }

        let now = Date.now
        let samples = [
            SavedItem(
                kind: .photo,
                title: "Floating glass controls",
                note: "The controls feel light, but still tactile.",
                createdAt: now.addingTimeInterval(-900),
                sourceURLString: "https://pinterest.com",
                isInbox: true,
                tagNames: ["UI", "Glass", "Controls"],
                accentHex: "70AEFF",
                visualSeed: 0
            ),
            SavedItem(
                kind: .photo,
                title: "Chunky keycaps",
                note: "Borrow the press depth, not the keyboard layout.",
                createdAt: now.addingTimeInterval(-7_200),
                sourceURLString: "https://are.na",
                isInbox: true,
                tagNames: ["UI", "Motion"],
                accentHex: "FFD83D",
                visualSeed: 1
            ),
            SavedItem(
                kind: .link,
                title: "Playful typography notes",
                note: "Rounded headlines with quieter body copy.",
                createdAt: now.addingTimeInterval(-86_400 * 4),
                sourceURLString: "https://developer.apple.com/design",
                isFavorite: true,
                isInbox: false,
                tagNames: ["Typography", "Brand"],
                accentHex: "FF8066",
                visualSeed: 2
            ),
            SavedItem(
                kind: .note,
                title: "What caught you?",
                note: "A prompt is more useful than an empty Notes field.",
                createdAt: now.addingTimeInterval(-86_400 * 18),
                isInbox: false,
                tagNames: ["Product", "Writing"],
                accentHex: "87E56D",
                visualSeed: 3
            ),
            SavedItem(
                kind: .photo,
                title: "Warm cream canvas",
                note: "Let saved images be the loudest part of the screen.",
                createdAt: now.addingTimeInterval(-86_400 * 92),
                lastViewedAt: now.addingTimeInterval(-86_400 * 70),
                isFavorite: true,
                isInbox: false,
                tagNames: ["Color", "Maybe"],
                accentHex: "7957FF",
                visualSeed: 4
            ),
        ]

        samples.forEach(context.insert)

        let idea = Idea(
            title: "Maybe app UI",
            note: "A local place where saved things turn into something.",
            coverItemID: samples[0].id,
            tagNames: ["Maybe", "UI"],
            accentHex: "7957FF",
            items: [samples[0], samples[1], samples[2]]
        )
        context.insert(idea)
        try? context.save()
    }
}
