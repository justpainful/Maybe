import Foundation

/// Builds the page that sits inside an exported `.maybe` package.
///
/// Opening a saved library on a laptop is a different act from saving on a
/// phone: months later the sentence you wrote is worth more than the picture
/// you kept, so the page leads with what you said and lets the photo support
/// it. Everything is inlined — no fetch, no network — because browsers refuse
/// to read sibling files from `file://`.
enum ExportPage {
    static let filename = "index.html"
    private static let placeholder = "/*__MAYBE_LIBRARY__*/"

    struct MediaLocation {
        var archivePath: String?
        var thumbnailArchivePath: String?
    }

    // MARK: Payload

    private struct Payload: Encodable {
        var exportedAt: String
        var counts: Counts
        var ideas: [IdeaEntry]
        var items: [ItemEntry]
    }

    private struct Counts: Encodable {
        var things: Int
        var photos: Int
        var ideas: Int
        var told: Int
    }

    private struct IdeaEntry: Encodable {
        var id: String
        var title: String
        var note: String
        var accent: String
        var itemIDs: [String]
    }

    private struct PhotoEntry: Encodable {
        var src: String
        var thumb: String?
        var w: Int
        var h: Int
    }

    private struct ItemEntry: Encodable {
        var id: String
        var kind: String
        var title: String
        var note: String
        var month: String
        var dateLabel: String
        var source: String?
        var url: String?
        var tags: [String]
        var ideas: [String]
        var photos: [PhotoEntry]
        var file: String?
        var fileExtension: String?
        var favourite: Bool
        var accent: String
        var haystack: String
    }

    // MARK: Rendering

    static func render(
        items: [SavedItem],
        ideas: [Idea],
        locations: [UUID: MediaLocation],
        exportedAt: Date = .now,
        template: String? = nil
    ) -> Data? {
        guard let template = template ?? loadTemplate() else { return nil }

        let ordered = items.sorted { $0.createdAt > $1.createdAt }
        let monthFormatter = DateFormatter()
        monthFormatter.locale = .current
        monthFormatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")

        let entries = ordered.map { item in
            entry(for: item, locations: locations, monthFormatter: monthFormatter)
        }

        let payload = Payload(
            exportedAt: exportedAt.formatted(date: .long, time: .omitted),
            counts: Counts(
                things: entries.count,
                photos: entries.reduce(0) { $0 + $1.photos.count },
                ideas: ideas.count,
                told: entries.filter { !$0.note.isEmpty }.count
            ),
            ideas: ideas.map { idea in
                IdeaEntry(
                    id: idea.id.uuidString,
                    title: idea.title,
                    note: idea.note,
                    accent: idea.accentHex,
                    itemIDs: idea.items.map(\.id.uuidString)
                )
            },
            items: entries
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let json = try? encoder.encode(payload),
              let jsonText = String(data: json, encoding: .utf8) else { return nil }

        // `</` would close the surrounding script tag early; JSON reads `<\/`
        // as the same character.
        let safeJSON = jsonText.replacingOccurrences(of: "</", with: "<\\/")
        return template.replacingOccurrences(of: placeholder, with: safeJSON).data(using: .utf8)
    }

    private static func entry(
        for item: SavedItem,
        locations: [UUID: MediaLocation],
        monthFormatter: DateFormatter
    ) -> ItemEntry {
        let photos: [PhotoEntry] = item.images.compactMap { attachment in
            guard let location = locations[attachment.id],
                  let archivePath = location.archivePath else { return nil }
            return PhotoEntry(
                src: encode("media/" + archivePath),
                thumb: location.thumbnailArchivePath.map { encode("thumbnails/" + $0) },
                w: Int(attachment.width),
                h: Int(attachment.height)
            )
        }

        let ideaTitles = item.ideas.map(\.title)
        let source = item.hostName
        let fileAttachment = item.media.first { $0.type == .file }

        return ItemEntry(
            id: item.id.uuidString,
            kind: item.kindRawValue,
            title: item.title,
            note: item.note,
            month: monthFormatter.string(from: item.createdAt),
            dateLabel: item.createdAt.formatted(date: .abbreviated, time: .omitted),
            source: source,
            url: item.sourceURLString,
            tags: item.tagNames,
            ideas: ideaTitles,
            photos: photos,
            file: fileAttachment?.originalFilename,
            fileExtension: item.fileExtension,
            favourite: item.isFavorite,
            accent: item.accentHex,
            haystack: ([item.title, item.note, source ?? "", fileAttachment?.originalFilename ?? ""]
                + item.tagNames + ideaTitles)
                .joined(separator: " ")
                .lowercased()
        )
    }

    private static func encode(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
    }

    private static func loadTemplate() -> String? {
        guard let url = Bundle.main.url(forResource: "MaybeExport", withExtension: "html") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
