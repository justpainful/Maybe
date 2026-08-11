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

    /// A single shared capture can carry several photos, so "share four photos
    /// to Maybe" stays one Maybe with four photos.
    static func enqueue(_ record: SharedCaptureRecord, payloads: [Data]) throws {
        guard let rootURL else { throw CocoaError(.fileNoSuchFile) }
        try prepare(rootURL)

        var records = loadRecords(from: rootURL)
        records.append(record)
        try write(records, to: rootURL)

        for (index, payload) in payloads.enumerated() {
            try payload.write(to: payloadURL(for: record.id, index: index, rootURL: rootURL), options: .atomic)
        }
    }

    static func enqueue(_ record: SharedCaptureRecord, payload: Data?) throws {
        try enqueue(record, payloads: payload.map { [$0] } ?? [])
    }

    static func pendingCaptures() -> [(record: SharedCaptureRecord, payloads: [Data])] {
        guard let rootURL else { return [] }
        return loadRecords(from: rootURL).map { record in
            (record, payloads(for: record.id, rootURL: rootURL))
        }
    }

    static func removeCaptureIDs(_ ids: Set<UUID>) {
        guard let rootURL else { return }
        let remaining = loadRecords(from: rootURL).filter { !ids.contains($0.id) }
        try? write(remaining, to: rootURL)
        for id in ids {
            try? FileManager.default.removeItem(at: legacyPayloadURL(for: id, rootURL: rootURL))
            for index in 0..<maximumPayloads {
                let url = payloadURL(for: id, index: index, rootURL: rootURL)
                guard FileManager.default.fileExists(atPath: url.path) else { break }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static let maximumPayloads = 12

    private static func payloads(for id: UUID, rootURL: URL) -> [Data] {
        var result: [Data] = []
        for index in 0..<maximumPayloads {
            guard let data = try? Data(contentsOf: payloadURL(for: id, index: index, rootURL: rootURL)) else { break }
            result.append(data)
        }
        if result.isEmpty, let legacy = try? Data(contentsOf: legacyPayloadURL(for: id, rootURL: rootURL)) {
            result.append(legacy)
        }
        return result
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

    private static func payloadURL(for id: UUID, index: Int, rootURL: URL) -> URL {
        rootURL.appending(path: "PendingPayloads/\(id.uuidString)-\(index).data")
    }

    private static func legacyPayloadURL(for id: UUID, rootURL: URL) -> URL {
        rootURL.appending(path: "PendingPayloads/\(id.uuidString).data")
    }
}

