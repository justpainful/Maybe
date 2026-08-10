import Foundation

struct SharedCaptureRecord: Codable, Identifiable, Sendable {
    var id: UUID
    var kindRawValue: String
    var title: String
    var thought: String
    var sourceURLString: String?
    var originalFilename: String?
    var ideaTitle: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        kindRawValue: String,
        title: String,
        thought: String = "",
        sourceURLString: String? = nil,
        originalFilename: String? = nil,
        ideaTitle: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.kindRawValue = kindRawValue
        self.title = title
        self.thought = thought
        self.sourceURLString = sourceURLString
        self.originalFilename = originalFilename
        self.ideaTitle = ideaTitle
        self.createdAt = createdAt
    }
}

enum MaybeSharedContainer {
    static let suiteName = "group.com.justpainful.Maybe"
    private static let recordsFilename = "pending-captures.json"
    private static let ideaTitlesKey = "maybe.idea-titles"

    static func enqueue(_ record: SharedCaptureRecord, payload: Data?) throws {
        guard let rootURL else { throw CocoaError(.fileNoSuchFile) }
        try prepare(rootURL)

        var records = loadRecords(from: rootURL)
        records.append(record)
        try write(records, to: rootURL)

        if let payload {
            try payload.write(to: payloadURL(for: record.id, rootURL: rootURL), options: .atomic)
        }
    }

    static func pendingCaptures() -> [(record: SharedCaptureRecord, payload: Data?)] {
        guard let rootURL else { return [] }
        return loadRecords(from: rootURL).map { record in
            (record, try? Data(contentsOf: payloadURL(for: record.id, rootURL: rootURL)))
        }
    }

    static func removeCaptureIDs(_ ids: Set<UUID>) {
        guard let rootURL else { return }
        let remaining = loadRecords(from: rootURL).filter { !ids.contains($0.id) }
        try? write(remaining, to: rootURL)
        ids.forEach { try? FileManager.default.removeItem(at: payloadURL(for: $0, rootURL: rootURL)) }
    }

    static var publishedIdeaTitles: [String] {
        UserDefaults(suiteName: suiteName)?.stringArray(forKey: ideaTitlesKey) ?? []
    }

    static func publishIdeaTitles(_ titles: [String]) {
        UserDefaults(suiteName: suiteName)?.set(titles.sorted(), forKey: ideaTitlesKey)
    }

    private static var rootURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
    }

    private static func prepare(_ rootURL: URL) throws {
        try FileManager.default.createDirectory(
            at: rootURL.appending(path: "PendingPayloads", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
    }

    private static func loadRecords(from rootURL: URL) -> [SharedCaptureRecord] {
        guard let data = try? Data(contentsOf: rootURL.appending(path: recordsFilename)) else { return [] }
        return (try? JSONDecoder().decode([SharedCaptureRecord].self, from: data)) ?? []
    }

    private static func write(_ records: [SharedCaptureRecord], to rootURL: URL) throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: rootURL.appending(path: recordsFilename), options: .atomic)
    }

    private static func payloadURL(for id: UUID, rootURL: URL) -> URL {
        rootURL.appending(path: "PendingPayloads/\(id.uuidString).data")
    }
}

