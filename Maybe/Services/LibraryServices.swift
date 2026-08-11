import CryptoKit
import Foundation
import ImageIO
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct LocalMediaStore {
    private let fileManager = FileManager.default

    private var rootURL: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "Maybe", directoryHint: .isDirectory)
    }

    func prepareDirectories() throws {
        for folder in ["Media/Images", "Media/Videos", "Media/Files", "Thumbnails", "Exports"] {
            try fileManager.createDirectory(
                at: rootURL.appending(path: folder, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
    }

    func write(_ data: Data, filename: String, kind: MediaKind) throws -> String {
        try prepareDirectories()
        let folder: String
        switch kind {
        case .image: folder = "Media/Images"
        case .video: folder = "Media/Videos"
        case .file: folder = "Media/Files"
        }

        let safeName = filename.replacingOccurrences(of: "/", with: "-")
        let relativePath = "\(folder)/\(UUID().uuidString)-\(safeName)"
        try data.write(to: rootURL.appending(path: relativePath), options: .atomic)
        return relativePath
    }

    func createThumbnail(from data: Data, maximumPixelSize: Int = 720) throws -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                ] as CFDictionary
              ),
              let thumbnailData = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.82) else {
            return nil
        }

        return try writeThumbnail(thumbnailData)
    }

    func writeThumbnail(_ data: Data) throws -> String {
        try prepareDirectories()
        let relativePath = "Thumbnails/\(UUID().uuidString).jpg"
        try data.write(to: rootURL.appending(path: relativePath), options: .atomic)
        return relativePath
    }

    func data(at relativePath: String) -> Data? {
        try? Data(contentsOf: rootURL.appending(path: relativePath))
    }

    func url(at relativePath: String) -> URL {
        rootURL.appending(path: relativePath)
    }

    func remove(at relativePath: String) {
        try? fileManager.removeItem(at: rootURL.appending(path: relativePath))
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum LibraryMutationService {
    @MainActor
    static func markReviewed(_ item: SavedItem, in context: ModelContext) throws {
        item.isInbox = false
        item.modifiedAt = .now
        try context.save()
    }

    @MainActor
    static func update(
        _ item: SavedItem,
        title: String,
        note: String,
        sourceURLString: String?,
        tagNames: [String],
        isInbox: Bool,
        in context: ModelContext
    ) throws {
        item.title = title
        item.note = note
        item.sourceURLString = sourceURLString
        item.tagNames = tagNames
        item.isInbox = isInbox
        item.modifiedAt = .now
        try context.save()
    }

    @MainActor
    static func update(
        _ idea: Idea,
        title: String,
        note: String,
        tagNames: [String],
        itemIDs: Set<UUID>,
        coverItemID: UUID?,
        from availableItems: [SavedItem],
        in context: ModelContext
    ) throws {
        idea.title = title
        idea.note = note
        idea.tagNames = tagNames
        idea.items = availableItems.filter { itemIDs.contains($0.id) }
        idea.coverItemID = idea.items.contains(where: { $0.id == coverItemID })
            ? coverItemID
            : idea.items.first?.id
        idea.modifiedAt = .now
        try context.save()
        MaybeSharedContainer.publishIdeaTitles(
            (try context.fetch(FetchDescriptor<Idea>())).map(\.title)
        )
    }

    @MainActor
    static func add(_ item: SavedItem, to idea: Idea, in context: ModelContext) throws {
        guard !idea.items.contains(where: { $0.id == item.id }) else { return }
        idea.items.append(item)
        idea.modifiedAt = .now
        item.isInbox = false
        item.modifiedAt = .now
        try context.save()
    }

    @MainActor
    static func delete(
        _ item: SavedItem,
        in context: ModelContext,
        mediaStore: LocalMediaStore = .init()
    ) throws {
        for attachment in item.media {
            mediaStore.remove(at: attachment.localPath)
            if let thumbnailPath = attachment.thumbnailPath {
                mediaStore.remove(at: thumbnailPath)
            }
        }
        context.delete(item)
        try context.save()
    }

    @MainActor
    static func delete(_ idea: Idea, in context: ModelContext) throws {
        context.delete(idea)
        try context.save()
        MaybeSharedContainer.publishIdeaTitles(
            (try context.fetch(FetchDescriptor<Idea>())).map(\.title)
        )
    }
}

enum ResurfacingEngine {
    static func pick(from items: [SavedItem], now: Date = .now) -> SavedItem? {
        items.max { lhs, rhs in
            score(lhs, now: now) < score(rhs, now: now)
        }
    }

    static func score(_ item: SavedItem, now: Date = .now) -> Double {
        let day: TimeInterval = 86_400
        let age = max(0, now.timeIntervalSince(item.createdAt) / day)
        let unseen = max(0, now.timeIntervalSince(item.lastViewedAt ?? item.createdAt) / day)
        let favoriteBoost = item.isFavorite ? 18.0 : 0
        let unconnectedBoost = item.ideas.isEmpty ? 12.0 : 0
        return min(age, 180) * 0.22 + min(unseen, 120) * 0.72 + favoriteBoost + unconnectedBoost
    }
}

enum ShareInboxImporter {
    @MainActor
    static func importPending(into context: ModelContext, mediaStore: LocalMediaStore = .init()) -> Int {
        let captures = MaybeSharedContainer.pendingCaptures()
        guard !captures.isEmpty else { return 0 }

        let ideas = (try? context.fetch(FetchDescriptor<Idea>())) ?? []
        let attachments = (try? context.fetch(FetchDescriptor<MediaAttachment>())) ?? []
        var existingHashes = Set(attachments.map(\.sha256))
        var importedIDs = Set<UUID>()
        var count = 0

        for capture in captures {
            let record = capture.record
            let hash = capture.payload.map(LocalMediaStore.hash)

            if let hash, existingHashes.contains(hash) {
                importedIDs.insert(record.id)
                continue
            }

            let item = SavedItem(
                id: record.id,
                kind: MaybeKind(rawValue: record.kindRawValue) ?? .note,
                title: record.title,
                note: record.thought,
                createdAt: record.createdAt,
                sourceURLString: record.sourceURLString,
                isInbox: true,
                accentHex: MaybePalette.accentHexes[count % MaybePalette.accentHexes.count],
                visualSeed: count % 5
            )
            context.insert(item)

            if let payload = capture.payload, let hash {
                let mediaKind: MediaKind = item.kind == .photo ? .image : .file
                if let path = try? mediaStore.write(
                    payload,
                    filename: record.originalFilename ?? "shared-item",
                    kind: mediaKind
                ) {
                    item.media.append(
                        MediaAttachment(
                            type: mediaKind,
                            localPath: path,
                            thumbnailPath: mediaKind == .image ? try? mediaStore.createThumbnail(from: payload) : nil,
                            originalFilename: record.originalFilename ?? "shared-item",
                            sha256: hash,
                            item: item
                        )
                    )
                    existingHashes.insert(hash)
                }
            }

            if let ideaTitle = record.ideaTitle,
               let idea = ideas.first(where: { $0.title == ideaTitle }) {
                idea.items.append(item)
                idea.modifiedAt = .now
            }

            importedIDs.insert(record.id)
            count += 1
        }

        try? context.save()
        MaybeSharedContainer.removeCaptureIDs(importedIDs)
        MaybeSharedContainer.publishIdeaTitles(ideas.map(\.title))
        return count
    }
}

extension UTType {
    static let maybeLibrary = UTType(exportedAs: "com.maybe.library", conformingTo: .package)
}

struct MaybeArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.maybeLibrary] }

    var wrapper: FileWrapper

    init(wrapper: FileWrapper = FileWrapper(directoryWithFileWrappers: [:])) {
        self.wrapper = wrapper
    }

    init(configuration: ReadConfiguration) throws {
        wrapper = configuration.file
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        wrapper
    }
}

enum LibraryArchiveService {
    struct Archive: Codable {
        var version: Int
        var exportedAt: Date
        var items: [ItemRecord]
        var ideas: [IdeaRecord]
    }

    struct ItemRecord: Codable {
        var id: UUID
        var kind: String
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
        var media: [MediaRecord]
    }

    struct MediaRecord: Codable {
        var id: UUID
        var type: String
        var originalFilename: String
        var sha256: String
        var width: Double
        var height: Double
        var archivePath: String?
        var thumbnailArchivePath: String?
        var data: Data?
    }

    struct IdeaRecord: Codable {
        var id: UUID
        var title: String
        var note: String
        var createdAt: Date
        var modifiedAt: Date
        var coverItemID: UUID?
        var tagNames: [String]
        var accentHex: String
        var itemIDs: [UUID]
    }

    static func exportPackage(
        items: [SavedItem],
        ideas: [Idea],
        mediaStore: LocalMediaStore = .init()
    ) throws -> FileWrapper {
        var mediaFiles: [String: FileWrapper] = [:]
        var thumbnailFiles: [String: FileWrapper] = [:]
        let itemRecords = items.map { item in
            ItemRecord(
                id: item.id,
                kind: item.kindRawValue,
                title: item.title,
                note: item.note,
                createdAt: item.createdAt,
                modifiedAt: item.modifiedAt,
                lastViewedAt: item.lastViewedAt,
                sourceURLString: item.sourceURLString,
                isFavorite: item.isFavorite,
                isInbox: item.isInbox,
                tagNames: item.tagNames,
                accentHex: item.accentHex,
                visualSeed: item.visualSeed,
                media: item.media.map { attachment in
                    let safeName = attachment.originalFilename
                        .replacingOccurrences(of: "/", with: "-")
                        .replacingOccurrences(of: "\\", with: "-")
                    let archivePath = "\(attachment.id.uuidString)-\(safeName)"
                    if let data = mediaStore.data(at: attachment.localPath) {
                        mediaFiles[archivePath] = FileWrapper(regularFileWithContents: data)
                    }
                    let thumbnailArchivePath = attachment.thumbnailPath.flatMap { path -> String? in
                        guard let data = mediaStore.data(at: path) else { return nil }
                        let name = "\(attachment.id.uuidString).jpg"
                        thumbnailFiles[name] = FileWrapper(regularFileWithContents: data)
                        return name
                    }
                    MediaRecord(
                        id: attachment.id,
                        type: attachment.typeRawValue,
                        originalFilename: attachment.originalFilename,
                        sha256: attachment.sha256,
                        width: attachment.width,
                        height: attachment.height,
                        archivePath: mediaFiles[archivePath] == nil ? nil : archivePath,
                        thumbnailArchivePath: thumbnailArchivePath,
                        data: nil
                    )
                }
            )
        }

        let ideaRecords = ideas.map { idea in
            IdeaRecord(
                id: idea.id,
                title: idea.title,
                note: idea.note,
                createdAt: idea.createdAt,
                modifiedAt: idea.modifiedAt,
                coverItemID: idea.coverItemID,
                tagNames: idea.tagNames,
                accentHex: idea.accentHex,
                itemIDs: idea.items.map(\.id)
            )
        }

        let archive = Archive(version: 2, exportedAt: .now, items: itemRecords, ideas: ideaRecords)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let libraryData = try encoder.encode(archive)
        return FileWrapper(directoryWithFileWrappers: [
            "library.json": FileWrapper(regularFileWithContents: libraryData),
            "media": FileWrapper(directoryWithFileWrappers: mediaFiles),
            "thumbnails": FileWrapper(directoryWithFileWrappers: thumbnailFiles),
        ])
    }

    @MainActor
    static func importPackage(
        wrapper: FileWrapper,
        into context: ModelContext,
        mediaStore: LocalMediaStore = .init()
    ) throws -> Int {
        guard wrapper.isDirectory,
              let children = wrapper.fileWrappers,
              let data = children["library.json"]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let archive = try JSONDecoder().decode(Archive.self, from: data)
        guard archive.version == 2 else { throw CocoaError(.fileReadUnsupportedScheme) }

        let mediaFiles = children["media"]?.fileWrappers ?? [:]
        let thumbnailFiles = children["thumbnails"]?.fileWrappers ?? [:]

        let existingItems = try context.fetch(FetchDescriptor<SavedItem>())
        let existingIdeas = try context.fetch(FetchDescriptor<Idea>())
        var existingHashes = Set(try context.fetch(FetchDescriptor<MediaAttachment>()).map(\.sha256))
        var itemsByID = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
        var importedCount = 0

        for record in archive.items where itemsByID[record.id] == nil {
            let item = SavedItem(
                id: record.id,
                kind: MaybeKind(rawValue: record.kind) ?? .note,
                title: record.title,
                note: record.note,
                createdAt: record.createdAt,
                modifiedAt: record.modifiedAt,
                lastViewedAt: record.lastViewedAt,
                sourceURLString: record.sourceURLString,
                isFavorite: record.isFavorite,
                isInbox: record.isInbox,
                tagNames: record.tagNames,
                accentHex: record.accentHex,
                visualSeed: record.visualSeed
            )
            context.insert(item)

            for media in record.media where !existingHashes.contains(media.sha256) {
                let payload = media.archivePath.flatMap { mediaFiles[$0]?.regularFileContents } ?? media.data
                guard let payload else { continue }
                let kind = MediaKind(rawValue: media.type) ?? .file
                let relativePath = try mediaStore.write(payload, filename: media.originalFilename, kind: kind)
                let thumbnailPath = media.thumbnailArchivePath
                    .flatMap { thumbnailFiles[$0]?.regularFileContents }
                    .flatMap { try? mediaStore.writeThumbnail($0) }
                    ?? (kind == .image ? try? mediaStore.createThumbnail(from: payload) : nil)
                item.media.append(
                    MediaAttachment(
                        id: media.id,
                        type: kind,
                        localPath: relativePath,
                        thumbnailPath: thumbnailPath,
                        width: media.width,
                        height: media.height,
                        originalFilename: media.originalFilename,
                        sha256: media.sha256,
                        item: item
                    )
                )
                existingHashes.insert(media.sha256)
            }

            itemsByID[item.id] = item
            importedCount += 1
        }

        let existingIdeaIDs = Set(existingIdeas.map(\.id))
        for record in archive.ideas where !existingIdeaIDs.contains(record.id) {
            let idea = Idea(
                id: record.id,
                title: record.title,
                note: record.note,
                createdAt: record.createdAt,
                modifiedAt: record.modifiedAt,
                coverItemID: record.coverItemID,
                tagNames: record.tagNames,
                accentHex: record.accentHex,
                items: record.itemIDs.compactMap { itemsByID[$0] }
            )
            context.insert(idea)
        }

        try context.save()
        return importedCount
    }
}
