import CryptoKit
import Foundation
import ImageIO
import Observation

struct GalleryPlate: Codable, Equatable {
    let id: String
    let description: String
    let aspectRatio: Double
    let wholeSubject: Bool?
    let video: String?
    let poster: String?
    var ambience: String? = nil
    var ambienceURL: URL? { GalleryCatalog.asset(ambience, extensions: ["m4a"]) }

    var localPoster: URL? { AppResources.url(id, extension: "jpg", folder: "LibraryContent/Gallery") }
    var filmURL: URL? { GalleryCatalog.asset(video, extensions: ["mp4"]) }
    var posterURL: URL? { GalleryCatalog.asset(poster, extensions: ["jpg", "jpeg"]) }
}

struct GalleryCatalog: Codable, Equatable {
    let schemaVersion: Int
    let plates: [GalleryPlate]

    // Only this discovery address is fixed. Each catalog controls its own media paths.
    static let endpoint = URL(string: "https://media.protomota.com/glimmer/gallery/gallery.json")!
    static let bundled = AppResources.url("Gallery", extension: "json", folder: "LibraryContent/Gallery")
        .flatMap { try? load($0) } ?? Self(schemaVersion: 1, plates: [])

    static func load(_ url: URL) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    static func asset(_ path: String?, extensions: Set<String>) -> URL? {
        guard let path, !path.isEmpty, path.utf8.count <= 500,
              path.range(of: #"^[A-Za-z0-9_-][A-Za-z0-9._-]*(/[A-Za-z0-9_-][A-Za-z0-9._-]*)*$"#, options: .regularExpression) == path.startIndex..<path.endIndex,
              extensions.contains((path as NSString).pathExtension.lowercased())
        else { return nil }
        return endpoint.deletingLastPathComponent().appending(path: path)
    }

    func validate(bundledIDs: Set<String>) throws {
        guard schemaVersion == 1, !plates.isEmpty, Set(plates.map(\.id)).count == plates.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for plate in plates {
            guard plate.id.utf8.count <= 96,
                  plate.id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) == plate.id.startIndex..<plate.id.endIndex,
                  !plate.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  plate.description.utf8.count <= 2048, (0.1...20).contains(plate.aspectRatio),
                  plate.video == nil || plate.filmURL != nil,
                  plate.poster == nil || plate.posterURL != nil,
                  plate.ambience == nil || (plate.filmURL != nil && plate.ambienceURL != nil),
                  plate.poster != nil || bundledIDs.contains(plate.id)
            else { throw CocoaError(.fileReadCorruptFile) }
        }
    }

    func pick(slot: Int, date: Date, aspect: Double, featured: Bool = false) -> GalleryPlate? {
        let films = featured ? plates.filter { $0.video != nil } : []
        let collection = films.isEmpty ? plates : films
        let fitting = collection.filter {
            $0.wholeSubject != true || abs(log($0.aspectRatio / max(0.01, aspect))) < 0.20
        }
        // A themed remote collection might consist entirely of portrait subjects.
        // Preserve the complete image with aspect fit in that case, even in a wide slot.
        let candidates = fitting.isEmpty ? collection : fitting
        guard !candidates.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return candidates[(day + slot) % candidates.count]
    }
}

private final class GalleryTransfer: NSObject, URLSessionDownloadDelegate {
    let limit: Int64
    init(limit: Int) { self.limit = Int64(limit) }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // R2 publishes the canonical endpoints directly.
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { downloadTask.cancel() }
    }
}

enum GalleryHTTP {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    static func fetch(_ request: URLRequest, limit: Int) async throws -> (Data, HTTPURLResponse) {
        let (file, response) = try await session.download(for: request, delegate: GalleryTransfer(limit: limit))
        defer { try? FileManager.default.removeItem(at: file) }
        guard let http = response as? HTTPURLResponse, http.url == request.url,
              [200,304].contains(http.statusCode) else { throw URLError(.badServerResponse) }
        if http.statusCode == 304 { return (Data(), http) }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let size, size > 0, size <= limit else { throw URLError(.dataLengthExceedsMaximum) }
        return (try Data(contentsOf: file), http)
    }
}

@Observable @MainActor
final class GalleryLibrary {
    struct Snapshot: Codable {
        let catalog: GalleryCatalog
        let etag: String?
        let checked: Date
    }

    static let shared = GalleryLibrary()
    private(set) var catalog: GalleryCatalog
    @ObservationIgnored private let location: URL
    @ObservationIgnored private let bundledIDs: Set<String>
    @ObservationIgnored private var snapshot: Snapshot?
    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var refreshing = false

    init(bundled: GalleryCatalog = .bundled, directory: URL = URL.applicationSupportDirectory.appending(path: "GlimmerMedia")) {
        location = directory.appending(path: "catalog-v1.json")
        bundledIDs = Set(bundled.plates.map(\.id))
        catalog = bundled
        if let bytes = try? Data(contentsOf: location), let saved = try? JSONDecoder().decode(Snapshot.self, from: bytes),
           (try? saved.catalog.validate(bundledIDs: bundledIDs)) != nil {
            snapshot = saved
            catalog = saved.catalog
        }
    }

    var secondsUntilRefresh: TimeInterval {
        if let checked = snapshot?.checked, checked.timeIntervalSinceNow > -6 * 3600 {
            return max(120, 6 * 3600 + checked.timeIntervalSinceNow)
        }
        return 15 * 60
    }

    func refreshIfNeeded(now: Date = .now,
                         fetch: (URLRequest, Int) async throws -> (Data, HTTPURLResponse) = GalleryHTTP.fetch) async {
        guard !refreshing, now.timeIntervalSince(snapshot?.checked ?? .distantPast) >= 6 * 3600,
              now.timeIntervalSince(lastAttempt ?? .distantPast) >= 120 else { return }
        refreshing = true
        lastAttempt = now
        defer { refreshing = false }
        var request = URLRequest(url: GalleryCatalog.endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(snapshot?.etag, forHTTPHeaderField: "If-None-Match")
        do {
            let (data, response) = try await fetch(request, 2 * 1024 * 1024)
            try Task.checkCancellation()
            let next: Snapshot
            if response.statusCode == 304, let previous = snapshot {
                next = Snapshot(catalog: previous.catalog, etag: previous.etag, checked: now)
            } else {
                guard response.statusCode == 200, data.count <= 2 * 1024 * 1024 else { return }
                let decoded = try JSONDecoder().decode(GalleryCatalog.self, from: data)
                try decoded.validate(bundledIDs: bundledIDs)
                next = Snapshot(catalog: decoded, etag: response.value(forHTTPHeaderField: "ETag"), checked: now)
            }
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(next).write(to: location, options: .atomic)
            snapshot = next
            if catalog != next.catalog { catalog = next.catalog }
        } catch {
            // A corrupt index or a temporary outage never replaces the last accepted snapshot.
            if Task.isCancelled { lastAttempt = nil }
        }
    }
}

actor GalleryPosters {
    static let shared = GalleryPosters()
    private let folder: URL
    private let fetch: @Sendable (URLRequest, Int) async throws -> (Data, HTTPURLResponse)
    private let memory = NSCache<NSURL, CGImage>()
    private var inFlight: [URL: Task<CGImage?, Never>] = [:]

    init(directory: URL = URL.cachesDirectory.appending(path: "GlimmerGalleryPosters"),
         fetch: @escaping @Sendable (URLRequest, Int) async throws -> (Data, HTTPURLResponse) = { try await GalleryHTTP.fetch($0, limit: $1) }) {
        folder = directory
        self.fetch = fetch
        memory.totalCostLimit = 24 * 1024 * 1024
    }

    private func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetType(source) as String? == "public.jpeg" else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1800,
                       kCGImageSourceShouldCacheImmediately: true, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    func image(for url: URL) async -> CGImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let task = inFlight[url] { return await task.value }
        let task = Task { await self.retrieve(url) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL, cost: image.height * image.bytesPerRow) }
        return image
    }

    private func retrieve(_ url: URL) async -> CGImage? {
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = folder.appending(path: name)
        if let data = try? Data(contentsOf: file), let image = decode(data) { return image }
        guard let (data, response) = try? await fetch(URLRequest(url: url), 4 * 1024 * 1024),
              response.statusCode == 200, let image = decode(data) else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            try trimDiskCache()
        } catch { /* The image is still available for this session. */ }
        return image
    }

    private func trimDiskCache() throws {
        let keys: Set<URLResourceKey> = [.fileSizeKey,.contentModificationDateKey]
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))
        let entries = try files.map { ($0, try $0.resourceValues(forKeys: keys)) }
        var bytes = entries.reduce(0) { $0 + ($1.1.fileSize ?? 0) }
        for (url, values) in entries.sorted(by: { ($0.1.contentModificationDate ?? .distantPast) < ($1.1.contentModificationDate ?? .distantPast) }) {
            guard bytes > 64 * 1024 * 1024 else { break }
            try FileManager.default.removeItem(at: url)
            bytes -= values.fileSize ?? 0
        }
    }
}
