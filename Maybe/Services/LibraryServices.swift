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

    /// Photo filenames carry a sortable timestamp so a gallery always shows
    /// photos in the order they were added, without extra schema.
    static func photoFilename(index: Int, date: Date = .now, fileExtension: String = "jpg") -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmssSSS"
        return String(format: "Photo-%@-%02d.%@", formatter.string(from: date), index + 1, fileExtension)
    }
}

// MARK: - Attaching media

enum MediaIngest {
    /// Writes a payload into the local media folder and links it to an item,
    /// always recording real pixel dimensions so layouts can respect the shape.
    @discardableResult
    @MainActor
    static func attach(
        _ payload: Data,
        kind: MediaKind,
        filename: String,
        to item: SavedItem,
        mediaStore: LocalMediaStore = .init()
    ) throws -> MediaAttachment {
        let path = try mediaStore.write(payload, filename: filename, kind: kind)
        let size = kind == .image ? pixelSize(of: payload) : .zero
        let attachment = MediaAttachment(
            type: kind,
            localPath: path,
            thumbnailPath: kind == .image ? try mediaStore.createThumbnail(from: payload) : nil,
            width: Double(size.width),
            height: Double(size.height),
            originalFilename: filename,
            sha256: LocalMediaStore.hash(payload),
            item: item
        )
        item.media.append(attachment)
        return attachment
    }

    static func pixelSize(of payload: Data) -> CGSize {
        guard let source = CGImageSourceCreateWithData(payload as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .zero
        }
        let width = (properties[kCGImagePropertyPixelWidth] as? Double) ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? Double) ?? 0
        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
        // Orientations 5...8 are stored rotated; report the displayed shape.
        return (5...8).contains(Int(orientation))
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
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
    static func addPhotos(_ payloads: [Data], to item: SavedItem, in context: ModelContext) throws {
        let existingHashes = Set(item.media.map(\.sha256))
        var added = 0
        for payload in payloads where !existingHashes.contains(LocalMediaStore.hash(payload)) {
            try MediaIngest.attach(
                payload,
                kind: .image,
                filename: LocalMediaStore.photoFilename(index: item.imageCount + added),
                to: item
            )
            added += 1
        }
        guard added > 0 else { return }
        item.modifiedAt = .now
        try context.save()
    }

    @MainActor
    static func removeMedia(
        _ attachment: MediaAttachment,
        from item: SavedItem,
        in context: ModelContext,
        mediaStore: LocalMediaStore = .init()
    ) throws {
        mediaStore.remove(at: attachment.localPath)
        if let thumbnailPath = attachment.thumbnailPath {
            mediaStore.remove(at: thumbnailPath)
        }
        item.media.removeAll { $0.id == attachment.id }
        context.delete(attachment)
        item.modifiedAt = .now
        try context.save()
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
            let hashes = capture.payloads.map(LocalMediaStore.hash)

            if !hashes.isEmpty, hashes.allSatisfy(existingHashes.contains) {
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

            let mediaKind: MediaKind = item.kind == .photo ? .image : .file
            for (index, payload) in capture.payloads.enumerated() where !existingHashes.contains(hashes[index]) {
                let filename = mediaKind == .image
                    ? LocalMediaStore.photoFilename(index: index)
                    : (record.originalFilename ?? "shared-item")
                if (try? MediaIngest.attach(
                    payload,
                    kind: mediaKind,
                    filename: filename,
                    to: item,
                    mediaStore: mediaStore
                )) != nil {
                    existingHashes.insert(hashes[index])
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

// MARK: - Sample library (QA only)

/// Only ever runs behind `--use-sample-data`, so screenshots exercise the real
/// media pipeline: real files on disk, real pixel sizes, real thumbnails.
enum SampleLibrarySeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        var descriptor = FetchDescriptor<SavedItem>()
        descriptor.fetchLimit = 1
        guard (try? context.fetch(descriptor))?.isEmpty == true else { return }

        let now = Date.now
        let day: TimeInterval = 86_400

        let buttons = SavedItem(
            kind: .photo,
            title: "Glass buttons on cream",
            note: "The way the light sits on the top edge.",
            createdAt: now.addingTimeInterval(-900),
            sourceURLString: "https://www.pinterest.com/pin/1042",
            isInbox: true,
            tagNames: ["UI", "Glass"],
            accentHex: "70AEFF"
        )
        let keycaps = SavedItem(
            kind: .photo,
            title: "Keycap depth",
            note: "Borrow the press, not the keyboard.",
            createdAt: now.addingTimeInterval(-4 * 3_600),
            sourceURLString: "https://www.are.na/block/889",
            isInbox: true,
            tagNames: ["Motion"],
            accentHex: "FFD83D"
        )
        let poster = SavedItem(
            kind: .photo,
            title: "Poster wall",
            createdAt: now.addingTimeInterval(-day * 2),
            isInbox: true,
            tagNames: ["Colour"],
            accentHex: "FF8066"
        )
        let typography = SavedItem(
            kind: .link,
            title: "Rounded headlines, quiet body",
            note: "Only the headline gets the personality.",
            createdAt: now.addingTimeInterval(-day * 5),
            sourceURLString: "https://developer.apple.com/design/human-interface-guidelines/typography",
            isFavorite: true,
            isInbox: false,
            tagNames: ["Typography"],
            accentHex: "87E56D"
        )
        let thought = SavedItem(
            kind: .note,
            title: "Save fast, sort never",
            note: "If saving takes more than three seconds I stop saving.",
            createdAt: now.addingTimeInterval(-day * 21),
            isInbox: false,
            tagNames: ["Product"],
            accentHex: "7957FF"
        )
        let palette = SavedItem(
            kind: .file,
            title: "Palette notes",
            createdAt: now.addingTimeInterval(-day * 40),
            isInbox: false,
            tagNames: ["Colour"],
            accentHex: "FFD83D"
        )
        let studio = SavedItem(
            kind: .photo,
            title: "Warm studio light",
            note: "Cream walls make everything else louder.",
            createdAt: now.addingTimeInterval(-day * 96),
            lastViewedAt: now.addingTimeInterval(-day * 74),
            isFavorite: true,
            isInbox: false,
            tagNames: ["Colour", "Light"],
            accentHex: "FF8066"
        )

        let all = [buttons, keycaps, poster, typography, thought, palette, studio]
        all.forEach(context.insert)

        attach(sizes: [(1200, 1600), (1600, 1100), (1080, 1080), (900, 1500)], seed: 0, to: buttons)
        attach(sizes: [(1500, 1000)], seed: 4, to: keycaps)
        attach(sizes: [(1100, 1500)], seed: 7, to: poster)
        attach(sizes: [(1400, 1400)], seed: 9, to: studio)

        let notes = Data("Cream F3F0E7 / Ink 171717 / Purple 7957FF\n".utf8)
        try? MediaIngest.attach(notes, kind: .file, filename: "palette-notes.txt", to: palette)

        let appIdea = Idea(
            title: "Maybe app UI",
            note: "A local place where saved things turn into something.",
            createdAt: now.addingTimeInterval(-day * 3),
            modifiedAt: now.addingTimeInterval(-3_600),
            coverItemID: buttons.id,
            tagNames: ["UI", "Glass"],
            accentHex: "7957FF",
            items: [buttons, keycaps, typography]
        )
        let roomIdea = Idea(
            title: "Studio wall",
            note: "What the corner by the window could become.",
            createdAt: now.addingTimeInterval(-day * 30),
            modifiedAt: now.addingTimeInterval(-day * 2),
            coverItemID: studio.id,
            tagNames: ["Colour"],
            accentHex: "FF8066",
            items: [studio, poster]
        )
        context.insert(appIdea)
        context.insert(roomIdea)

        try? context.save()
    }

    @MainActor
    private static func attach(sizes: [(Int, Int)], seed: Int, to item: SavedItem) {
        for (offset, size) in sizes.enumerated() {
            guard let payload = SamplePhotoFactory.jpeg(width: size.0, height: size.1, seed: seed + offset) else {
                continue
            }
            try? MediaIngest.attach(
                payload,
                kind: .image,
                filename: LocalMediaStore.photoFilename(index: offset),
                to: item
            )
        }
    }
}

/// Stand-in photographs for QA runs. The app never draws artwork for real
/// saved items — a saved thing only ever shows its own content.
enum SamplePhotoFactory {
    private static let palette: [UIColor] = [
        UIColor(red: 0.475, green: 0.341, blue: 1.000, alpha: 1),
        UIColor(red: 1.000, green: 0.847, blue: 0.239, alpha: 1),
        UIColor(red: 0.439, green: 0.682, blue: 1.000, alpha: 1),
        UIColor(red: 0.529, green: 0.898, blue: 0.427, alpha: 1),
        UIColor(red: 1.000, green: 0.502, blue: 0.400, alpha: 1),
    ]
    private static let canvas = UIColor(red: 0.953, green: 0.941, blue: 0.906, alpha: 1)

    @MainActor
    static func jpeg(width: Int, height: Int, seed: Int) -> Data? {
        let size = CGSize(width: width, height: height)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        var generator = SeededGenerator(seed: UInt64(abs(seed) &+ 7) &* 2_654_435_761)
        let base = palette[abs(seed) % palette.count]

        let partner = palette[(abs(seed) + 3) % palette.count]

        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cgContext = context.cgContext
            let bounds = CGRect(origin: .zero, size: size)

            canvas.setFill()
            cgContext.fill(bounds)

            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    base.withAlphaComponent(0.92).cgColor,
                    partner.withAlphaComponent(0.92).cgColor,
                ] as CFArray,
                locations: [0, 1]
            ) {
                cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            let shapeCount = 4 + Int(generator.next() % 3)
            for index in 0..<shapeCount {
                let color = palette[(abs(seed) + index + 1) % palette.count]
                let shapeWidth = size.width * CGFloat(0.26 + Double(generator.next() % 34) / 100)
                let shapeHeight = size.height * CGFloat(0.20 + Double(generator.next() % 34) / 100)
                let originX = CGFloat(Double(generator.next() % 80) / 100) * size.width - shapeWidth * 0.15
                let originY = CGFloat(Double(generator.next() % 80) / 100) * size.height - shapeHeight * 0.15
                let rect = CGRect(x: originX, y: originY, width: shapeWidth, height: shapeHeight)
                let radius = min(shapeWidth, shapeHeight) * (index.isMultiple(of: 2) ? 0.5 : 0.14)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
                color.withAlphaComponent(0.9).setFill()
                path.fill()
                UIColor.white.withAlphaComponent(0.42).setStroke()
                path.lineWidth = max(2, min(size.width, size.height) * 0.01)
                path.stroke()
            }

            // A soft top-light and a darker floor, so these read as photographs
            // of objects rather than flat swatches.
            if let sheen = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.white.withAlphaComponent(0.34).cgColor,
                    UIColor.white.withAlphaComponent(0).cgColor,
                    UIColor.black.withAlphaComponent(0.22).cgColor,
                ] as CFArray,
                locations: [0, 0.55, 1]
            ) {
                cgContext.drawLinearGradient(
                    sheen,
                    start: .zero,
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }
        }
        return image.jpegData(compressionQuality: 0.9)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
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
        var locations: [UUID: ExportPage.MediaLocation] = [:]
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
                    let storedPath = mediaFiles[archivePath] == nil ? nil : archivePath
                    locations[attachment.id] = ExportPage.MediaLocation(
                        archivePath: storedPath,
                        thumbnailArchivePath: thumbnailArchivePath
                    )
                    return MediaRecord(
                        id: attachment.id,
                        type: attachment.typeRawValue,
                        originalFilename: attachment.originalFilename,
                        sha256: attachment.sha256,
                        width: attachment.width,
                        height: attachment.height,
                        archivePath: storedPath,
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
        var children: [String: FileWrapper] = [
            "library.json": FileWrapper(regularFileWithContents: libraryData),
            "media": FileWrapper(directoryWithFileWrappers: mediaFiles),
            "thumbnails": FileWrapper(directoryWithFileWrappers: thumbnailFiles),
        ]

        // A library you can read without the app: open this in any browser.
        if let page = ExportPage.render(items: items, ideas: ideas, locations: locations) {
            children[ExportPage.filename] = FileWrapper(regularFileWithContents: page)
        }

        return FileWrapper(directoryWithFileWrappers: children)
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
