import Foundation
import Observation

/// One public document provides the coaching library and the media index.
struct EditorialEdition: Decodable {
    let schemaVersion: Int
    let content: Catalog
    let gallery: GalleryCatalog

    func validate(against bundled: Catalog, bundledGallery: GalleryCatalog) throws {
        let lessons = content.lessons
        let originalLessons = bundled.lessons
        let lessonIDs = lessons.map(\.id)
        let stableLessons = zip(originalLessons, lessons).allSatisfy { original, replacement in
            original.id == replacement.id
                && original.pages.map(\.kind) == replacement.pages.map(\.kind)
                && zip(original.pages, replacement.pages).allSatisfy { $0.options?.count == $1.options?.count }
        }
        let validOnboarding = bundled.onboarding.count == content.onboarding.count
            && zip(bundled.onboarding, content.onboarding).allSatisfy { original, replacement in
                original.kind == replacement.kind && original.key == replacement.key
                    && original.mode == replacement.mode
                    && original.options?.map(\.id) == replacement.options?.map(\.id)
            }
        guard schemaVersion == 1, lessons.count >= originalLessons.count, stableLessons,
              lessons.map(\.number) == Array(1...lessons.count),
              Set(lessonIDs).count == lessons.count,
              lessons.allSatisfy({ !$0.title.isEmpty && !$0.pages.isEmpty }),
              validOnboarding,
              Set(bundled.startingPractices.keys).isSubset(of: Set(content.startingPractices.keys)),
              preserves(bundled.challenges.map(\.id), in: content.challenges.map(\.id)),
              preserves(bundled.habits.map(\.id), in: content.habits.map(\.id)),
              content.energy.map(\.id) == bundled.energy.map(\.id),
              preserves(bundled.practiceTopics.map(\.id), in: content.practiceTopics.map(\.id)),
              preserves(bundled.practiceTopics.flatMap { $0.exercises.map(\.id) },
                        in: content.practiceTopics.flatMap { $0.exercises.map(\.id) }),
              preserves(bundled.cleaning.rooms.map(\.id), in: content.cleaning.rooms.map(\.id)),
              preserves(bundled.cleaning.speed.map(\.id), in: content.cleaning.speed.map(\.id)),
              content.cleaning.daily.id == bundled.cleaning.daily.id,
              validSeasonal(against: bundled),
              validQuotes(against: bundled) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try gallery.validate(bundledIDs: Set(bundledGallery.plates.map(\.id)))
    }

    private func validQuotes(against bundled: Catalog) -> Bool {
        guard let quotes = content.quotes else { return true }
        let original = bundled.quotes ?? []
        let ids = quotes.map(\.id)
        return Array(ids.prefix(original.count)) == original.map(\.id)
            && Set(ids).count == ids.count
            && quotes.allSatisfy {
                !$0.id.isEmpty && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    private func validSeasonal(against bundled: Catalog) -> Bool {
        guard let editions = content.seasonal else { return true }
        let original = bundled.seasonal ?? []
        guard preserves(original.map(\.id), in: editions.map(\.id)) else { return false }
        let maintenance = Set((content.cleaning.maintenance ?? bundled.cleaning.maintenance ?? []).map(\.id))
        return editions.allSatisfy { edition in
            let baseline = original.first { $0.id == edition.id }
            return PracticeDate.parse("2000-" + edition.start) != nil
                && PracticeDate.parse("2000-" + edition.end) != nil
                && (baseline == nil || baseline?.start == edition.start)
                && preserves(baseline?.tips.map(\.id) ?? [], in: edition.tips.map(\.id))
                && preserves(baseline?.checklists.map(\.id) ?? [], in: edition.checklists.map(\.id))
                && (edition.resources ?? []).allSatisfy { $0.url.scheme == "https" && $0.url.host != nil }
                && Set(edition.maintenance).isSubset(of: maintenance)
                && edition.checklists.allSatisfy { list in
                    let originalItems = baseline?.checklists.first { $0.id == list.id }?.items ?? []
                    return !list.items.isEmpty && preserves(originalItems.map(\.id), in: list.items.map(\.id))
                }
        }
    }

    private func preserves(_ old: [String], in new: [String]) -> Bool {
        let ids = Set(new)
        return new.count == ids.count && Set(old).isSubset(of: ids)
    }
}

@MainActor @Observable
final class EditorialLibrary {
    static let endpoint = URL(string: "https://media.protomota.com/glimmer/content/library-v1.json")!
    nonisolated static let defaultDirectory = URL.applicationSupportDirectory.appending(path: "GlimmerMedia")
    static let maxBytes = 2 * 1024 * 1024
    static let refreshInterval: TimeInterval = 15 * 60

    private struct Snapshot: Codable {
        let bytes: Data
        let etag: String?
    }

    private(set) var edition: EditorialEdition?
    @ObservationIgnored private var snapshot: Snapshot?
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private let file: URL
    @ObservationIgnored private let bundled: Catalog
    @ObservationIgnored private let bundledGallery: GalleryCatalog

    init(bundled: Catalog, bundledGallery: GalleryCatalog = .bundled, directory: URL = defaultDirectory) {
        self.bundled = bundled
        self.bundledGallery = bundledGallery
        file = directory.appending(path: "editorial-v1.json")
        if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size < 3 * Self.maxBytes,
           let bytes = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: bytes),
           let accepted = try? decode(saved.bytes) {
            snapshot = saved
            edition = accepted
        }
    }

    func refreshIfNeeded(now: Date = .now,
                         fetch: (URLRequest, Int) async throws -> (Data, HTTPURLResponse) = GalleryHTTP.fetch) async {
        guard !refreshing, now.timeIntervalSince(lastAttempt ?? .distantPast) >= Self.refreshInterval else { return }
        refreshing = true
        lastAttempt = now
        defer { refreshing = false }

        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(snapshot?.etag, forHTTPHeaderField: "If-None-Match")
        do {
            let (bytes, response) = try await fetch(request, Self.maxBytes)
            try Task.checkCancellation()
            guard response.url == Self.endpoint, response.statusCode == 200,
                  response.mimeType == "application/json" else { return }
            let accepted = try decode(bytes)
            let next = Snapshot(bytes: bytes, etag: response.value(forHTTPHeaderField: "ETag"))
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: file, options: .atomic)
            snapshot = next
            edition = accepted
        } catch {
            // No partially downloaded or rejected edition replaces the last valid edition.
            if Task.isCancelled { lastAttempt = nil }
        }
    }

    private func decode(_ bytes: Data) throws -> EditorialEdition {
        guard bytes.count <= Self.maxBytes else { throw URLError(.dataLengthExceedsMaximum) }
        let edition = try JSONDecoder().decode(EditorialEdition.self, from: bytes)
        try edition.validate(against: bundled, bundledGallery: bundledGallery)
        if let current = self.edition {
            try edition.validate(against: current.content, bundledGallery: bundledGallery)
        }
        return edition
    }
}
