import CryptoKit
import Foundation

struct JournalCloudState: Codable {
    var enabled = false
    var device = UUID()
    var account: Data?
    var acceptAccountChange = false
    var replica: JournalReplica
}

/// Keep the journal readable by existing releases, backups and the local MCP command.
struct SavedJournal: Codable {
    var journal: Journal
    var cloud: JournalCloudState?

    private enum CodingKeys: String, CodingKey { case cloud = "_glimmerCloud" }

    init(journal: Journal, cloud: JournalCloudState?) {
        self.journal = journal
        self.cloud = cloud
    }

    init(from decoder: Decoder) throws {
        journal = try Journal(from: decoder)
        cloud = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(JournalCloudState.self, forKey: .cloud)
    }

    func encode(to encoder: Encoder) throws {
        try journal.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(cloud, forKey: .cloud)
    }
}

/// Each installation writes its own file. No device has to overwrite another device's snapshot.
@MainActor
final class JournalCloud {
    struct Connection: Equatable, Sendable {
        let folder: URL
        let account: Data
    }

    struct Exchange: Sendable {
        var remote = JournalReplica()
        var own: JournalReplica?
        var downloading = false
    }

    private var query: NSMetadataQuery?
    private var connection: Connection?

    nonisolated static let container = "iCloud.com.protomota.glimmer"
    nonisolated static let fileExtension = "glimmerjournal"

    func stop() {
        query?.stop()
        query = nil
        connection = nil
    }

    func files(in connection: Connection) throws -> [URL]? {
        if self.connection != connection {
            stop()
            let query = NSMetadataQuery()
            query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
            query.predicate = NSPredicate(format: "%K ENDSWITH %@", NSMetadataItemFSNameKey, "." + Self.fileExtension)
            guard query.start() else { throw CocoaError(.fileReadUnknown) }
            self.query = query
            self.connection = connection
        }
        guard let query, !query.isGathering else { return nil }
        query.disableUpdates()
        defer { query.enableUpdates() }
        let folder = connection.folder.standardizedFileURL.path
        return query.results.compactMap { result in
            guard let item = result as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  url.deletingLastPathComponent().standardizedFileURL.path == folder,
                  UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil else { return nil }
            return url
        }
    }

    nonisolated static func connect() throws -> Connection? {
        guard let account = identity(),
              let root = FileManager.default.url(forUbiquityContainerIdentifier: container) else { return nil }
        try requireAccount(account)
        let folder = root.appending(path: "JournalV1", directoryHint: .isDirectory)
        return Connection(folder: folder, account: account)
    }

    nonisolated static func pull(_ files: [URL], device: UUID, in connection: Connection) throws -> Exchange {
        try requireAccount(connection.account)
        var exchange = Exchange()
        for file in files {
            let metadata = try file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = metadata.ubiquitousItemDownloadingStatus, status != .current {
                try FileManager.default.startDownloadingUbiquitousItem(at: file)
                exchange.downloading = true
                continue
            }
            let saved = try read(file)
            exchange.remote.merge(saved)
            if UUID(uuidString: file.deletingPathExtension().lastPathComponent) == device { exchange.own = saved }
        }
        try requireAccount(connection.account)
        return exchange
    }

    nonisolated static func push(_ replica: JournalReplica, device: UUID, in connection: Connection) throws -> Bool {
        try requireAccount(connection.account)
        let url = connection.folder.appending(path: device.uuidString + "." + fileExtension)
        try FileManager.default.createDirectory(at: connection.folder, withIntermediateDirectories: true)
        try write(replica, to: url) { try requireAccount(connection.account) }
        return try uploaded(device: device, in: connection)
    }

    nonisolated static func uploaded(device: UUID, in connection: Connection) throws -> Bool {
        try requireAccount(connection.account)
        let url = connection.folder.appending(path: device.uuidString + "." + fileExtension)
        return try url.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey]).ubiquitousItemIsUploaded == true
    }

    nonisolated static func read(_ file: URL) throws -> JournalReplica {
        var coordinationError: NSError?
        var readResult: Result<JournalReplica, Error>?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &coordinationError) { url in
            readResult = Result {
                let decoder = JSONDecoder()
                var merged = try decoder.decode(JournalReplica.self, from: Data(contentsOf: url))
                for conflict in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
                    let version = try decoder.decode(JournalReplica.self, from: Data(contentsOf: conflict.url))
                    merged.merge(version)
                }
                return merged
            }
        }
        if let coordinationError { throw coordinationError }
        guard let readResult else { throw CocoaError(.fileReadUnknown) }
        return try readResult.get()
    }

    nonisolated static func write(_ replica: JournalReplica, to file: URL, beforeWrite: () throws -> Void = {}) throws {
        let data = try JSONEncoder().encode(replica)
        var coordinationError: NSError?
        var writeResult: Result<Void, Error>?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { url in
            writeResult = Result {
                try beforeWrite()
                try data.write(to: url, options: .atomic)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let writeResult else { throw CocoaError(.fileWriteUnknown) }
        try writeResult.get()
    }

    private nonisolated static func identity() -> Data? {
        guard let token = FileManager.default.ubiquityIdentityToken,
              let encoded = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else { return nil }
        return Data(SHA256.hash(data: encoded))
    }

    private nonisolated static func requireAccount(_ account: Data) throws {
        guard identity() == account else { throw CocoaError(.userCancelled) }
    }
}
