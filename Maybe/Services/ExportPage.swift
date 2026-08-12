import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

    /// Photos either sit in folders beside the page, or travel inside it.
    /// A single idea or a single thing has to be one file you can hand over.
    enum Media {
        case folder([UUID: MediaLocation])
        case inlined(LocalMediaStore)
    }

    struct Scope: Encodable {
        var kind: String
        var title: String
        var kicker: String
        var line: String
        var note: String?

        static let library = Scope(
            kind: "library",
            title: "Library",
            kicker: "Library",
            line: "Everything that caught you, and what you said about it."
        )

        static func idea(_ idea: Idea) -> Scope {
            Scope(
                kind: "idea",
                title: idea.title,
                kicker: "One idea",
                line: idea.title,
                note: idea.note.isEmpty ? nil : idea.note
            )
        }

        static func item(_ item: SavedItem) -> Scope {
            Scope(
                kind: "item",
                title: item.title,
                kicker: "One thing",
                line: item.note.isEmpty ? item.title : item.note,
                note: item.note.isEmpty ? nil : item.title
            )
        }
    }

    // MARK: Payload

    private struct Payload: Encodable {
        var exportedAt: String
        var scope: Scope
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
        var tags: [String]
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
        render(
            scope: .library,
            items: items,
            ideas: ideas,
            media: .folder(locations),
            exportedAt: exportedAt,
            template: template
        )
    }

    static func render(
        scope: Scope,
        items: [SavedItem],
        ideas: [Idea],
        media: Media,
        exportedAt: Date = .now,
        template: String? = nil
    ) -> Data? {
        guard let template = template ?? loadTemplate() else { return nil }

        let ordered = items.sorted { $0.createdAt > $1.createdAt }
        let monthFormatter = DateFormatter()
        monthFormatter.locale = .current
        monthFormatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")

        let entries = ordered.map { item in
            entry(for: item, media: media, monthFormatter: monthFormatter)
        }

        let payload = Payload(
            exportedAt: exportedAt.formatted(date: .long, time: .omitted),
            scope: scope,
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
                    tags: idea.tagNames,
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
        media: Media,
        monthFormatter: DateFormatter
    ) -> ItemEntry {
        let photos: [PhotoEntry] = item.images.compactMap { attachment in
            switch media {
            case .folder(let locations):
                guard let location = locations[attachment.id],
                      let archivePath = location.archivePath else { return nil }
                return PhotoEntry(
                    src: encode("media/" + archivePath),
                    thumb: location.thumbnailArchivePath.map { encode("thumbnails/" + $0) },
                    w: Int(attachment.width),
                    h: Int(attachment.height)
                )
            case .inlined(let store):
                // The thumbnail is 720px: sharp on screen, and still around
                // 200dpi at the size a plate prints.
                let path = attachment.thumbnailPath ?? attachment.localPath
                guard let data = store.data(at: path) else { return nil }
                let uri = "data:image/jpeg;base64," + data.base64EncodedString()
                return PhotoEntry(
                    src: uri,
                    thumb: uri,
                    w: Int(attachment.width),
                    h: Int(attachment.height)
                )
            }
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

// MARK: - Handing one thing over

/// A single page you can save anywhere and open in any browser.
struct HTMLPageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.html] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension ExportPage {
    static func page(for idea: Idea, store: LocalMediaStore = .init()) -> HTMLPageDocument? {
        render(
            scope: .idea(idea),
            items: idea.items,
            ideas: [idea],
            media: .inlined(store)
        ).map(HTMLPageDocument.init)
    }

    static func page(for item: SavedItem, store: LocalMediaStore = .init()) -> HTMLPageDocument? {
        render(
            scope: .item(item),
            items: [item],
            ideas: [],
            media: .inlined(store)
        ).map(HTMLPageDocument.init)
    }

    /// A filename that reads like the thing itself rather than an export id.
    static func filename(for title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Maybe" : String(cleaned.prefix(60))
    }
}

/// What lands on the clipboard: rich enough to paste into a note or a mail,
/// plain enough to paste into a message.
enum ExportClipboard {
    @MainActor
    static func copy(_ item: SavedItem, store: LocalMediaStore = .init()) {
        write(html: snippet(for: item, store: store), text: text(for: item))
    }

    @MainActor
    static func copy(_ idea: Idea, store: LocalMediaStore = .init()) {
        let body = idea.items.map { snippet(for: $0, store: store) }.joined()
        let heading = """
        <h2 style="font:700 20px -apple-system,system-ui,sans-serif;margin:0 0 6px">\(escape(idea.title))</h2>
        \(idea.note.isEmpty ? "" : "<p style=\"font:15px -apple-system,system-ui,sans-serif;color:#555;margin:0 0 18px\">\(escape(idea.note))</p>")
        """
        let text = ([idea.title, idea.note].filter { !$0.isEmpty }
            + idea.items.map { self.text(for: $0) })
            .joined(separator: "\n\n")
        write(html: "<div>\(heading)\(body)</div>", text: text)
    }

    @MainActor
    private static func write(html: String, text: String) {
        UIPasteboard.general.setItems([[
            UTType.html.identifier: html,
            UTType.utf8PlainText.identifier: text,
        ]])
        MaybeHaptics.saved()
    }

    private static func snippet(for item: SavedItem, store: LocalMediaStore) -> String {
        var parts: [String] = []
        if !item.note.isEmpty {
            parts.append("<p style=\"font:700 17px -apple-system,system-ui,sans-serif;margin:0 0 6px\">\(escape(item.note))</p>")
        } else {
            parts.append("<p style=\"font:700 17px -apple-system,system-ui,sans-serif;margin:0 0 6px\">\(escape(item.title))</p>")
        }

        var meta = [item.createdAt.formatted(date: .abbreviated, time: .omitted)]
        if let host = item.hostName { meta.append(host) }
        meta.append(contentsOf: item.tagNames)
        parts.append("<p style=\"font:12px ui-monospace,monospace;color:#888;margin:0 0 10px\">\(escape(meta.joined(separator: " · ")))</p>")

        for attachment in item.images.prefix(4) {
            let path = attachment.thumbnailPath ?? attachment.localPath
            guard let data = store.data(at: path) else { continue }
            parts.append("<img src=\"data:image/jpeg;base64,\(data.base64EncodedString())\" style=\"max-width:100%;border-radius:8px;margin:0 0 8px\">")
        }

        if let url = item.sourceURLString {
            parts.append("<p style=\"font:13px -apple-system,system-ui,sans-serif;margin:0 0 18px\"><a href=\"\(escape(url))\">\(escape(item.hostName ?? url))</a></p>")
        }

        return "<div style=\"margin:0 0 22px\">\(parts.joined())</div>"
    }

    private static func text(for item: SavedItem) -> String {
        var lines: [String] = []
        lines.append(item.note.isEmpty ? item.title : item.note)
        if !item.note.isEmpty, item.title != item.note { lines.append(item.title) }
        var meta = [item.createdAt.formatted(date: .abbreviated, time: .omitted)]
        meta.append(contentsOf: item.tagNames)
        lines.append(meta.joined(separator: " · "))
        if let url = item.sourceURLString { lines.append(url) }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
