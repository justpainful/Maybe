import CoreGraphics
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

// MARK: - Presentation helpers

extension SavedItem {
    /// Photos in the order they were added. Media filenames carry a sortable
    /// timestamp prefix, so this stays stable across launches.
    var images: [MediaAttachment] {
        media
            .filter { $0.type == .image }
            .sorted { $0.originalFilename < $1.originalFilename }
    }

    var primaryImage: MediaAttachment? { images.first }

    var imageCount: Int { images.count }

    var hostName: String? {
        guard let sourceURLString, let host = URL(string: sourceURLString)?.host() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var fileExtension: String? {
        let name = media.first?.originalFilename ?? ""
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? nil : ext.uppercased()
    }

    /// The proportion a preview should be drawn at. Photos keep their own shape,
    /// so nothing is ever cropped to fill a grid cell.
    var previewAspect: CGFloat {
        if let image = primaryImage, image.width > 0, image.height > 0 {
            return MediaAspect.ratio(width: image.width, height: image.height)
        }
        switch kind {
        case .note: return 0.88
        case .link: return 1.3
        case .file: return 1.3
        case .photo: return 1
        }
    }

    /// One line of context for compact rows: the thought if there is one, then
    /// where it came from. Never a storage filename we made up ourselves.
    var subtitleLine: String {
        if !note.isEmpty { return note }
        if let hostName { return hostName }
        if kind == .file, let filename = media.first?.originalFilename { return filename }
        return createdAt.formatted(date: .abbreviated, time: .omitted)
    }
}

extension Idea {
    var coverItem: SavedItem? {
        if let coverItemID, let match = items.first(where: { $0.id == coverItemID }) {
            return match
        }
        return items.first
    }
}
