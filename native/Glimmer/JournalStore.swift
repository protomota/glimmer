import Foundation
import Observation

@MainActor
@Observable
final class JournalStore {
    private let bundledCatalog: Catalog?
    let editorialLibrary: EditorialLibrary?
    var catalog: Catalog? { editorialLibrary?.edition?.content ?? bundledCatalog }
    var maintenanceChores: [MaintenanceChore] {
        catalog?.cleaning.maintenance ?? bundledCatalog?.cleaning.maintenance ?? []
    }
    var seasonalEditions: [SeasonalEdition] { catalog?.seasonal ?? bundledCatalog?.seasonal ?? [] }
    var dailyQuote: DailyQuote? {
        DailyQuote.quote(on: day, from: catalog?.quotes ?? bundledCatalog?.quotes ?? [])
    }
    private(set) var journal = Journal()
    private(set) var loadError: String?
    var notice: String?
    private(set) var earnedCoins: EarnedCoins?
    var showingOnboardingReplay = false
    var day = Date()
    private let url: URL
    private let cloud: JournalCloud?
    private var cloudState: JournalCloudState?
    private var syncing = false
    private var cloudGeneration = UUID()
    private(set) var cloudStatus = "Journal stays on this device."
    private(set) var accountStatus = "Not checked"
    private(set) var lastCheck: Date?
    private(set) var lastCloudContact: Date?
    private(set) var syncErrorCode: String?
    var cloudSyncing: Bool { syncing }

    var cloudEnabled: Bool { cloudState?.enabled == true }
    var canUseCloud: Bool { cloud != nil && loadError == nil }

    init(url: URL? = nil, catalogURL: URL? = AppResources.url("Catalog", extension: "json")) {
        self.url = url ?? Self.storageURL
        // An explicitly isolated journal must never join the signed-in user's iCloud account.
        cloud = url == nil && Self.testJournalID == nil ? JournalCloud() : nil
        let baseline = catalogURL.flatMap { try? Catalog.load(from: $0) }
        bundledCatalog = baseline
        editorialLibrary = url == nil && Self.testJournalID == nil
            ? baseline.map { EditorialLibrary(bundled: $0) } : nil
        reload()
        #if os(macOS)
        if url == nil { watchForAgentChanges() }
        #endif
    }

    private nonisolated static var testJournalID: UUID? {
        #if DEBUG
        ProcessInfo.processInfo.environment["GLIMMER_TEST_JOURNAL"].flatMap(UUID.init(uuidString:))
        #else
        nil
        #endif
    }

    var usesDeviceReminders: Bool {
        Self.testJournalID == nil || ProcessInfo.processInfo.environment["GLIMMER_TEST_REMINDERS"] == "1"
    }

    nonisolated static var storageURL: URL {
        let folder = testJournalID.map { "Glimmer-Test-\($0.uuidString)" } ?? "Glimmer"
        let root = URL.applicationSupportDirectory.appending(path: folder, directoryHint: .isDirectory)
        return root.appending(path: "Journal.json")
    }

    #if os(macOS)
    private(set) var agentLevel = AgentAccess.Level.off
    private(set) var agentActivity: AgentActivity?
    private var diskStamp: Date?
    private var watcher: DispatchSourceFileSystemObject?

    private var folder: URL { url.deletingLastPathComponent() }

    /// Off removes both permissions. Changes also turns on summaries, because it includes them.
    func setAgentLevel(_ level: AgentAccess.Level) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, wanted) in [(AgentAccess.marker, level != .off), (AgentAccess.changesMarker, level == .changes)] {
            let file = folder.appending(path: name)
            if wanted && !manager.fileExists(atPath: file.path) {
                try Data().write(to: file, options: .atomic)
            } else if !wanted && manager.fileExists(atPath: file.path) {
                try manager.removeItem(at: file)
            }
        }
        refreshAgentState()
    }

    func refreshAgentState() {
        agentLevel = AgentAccess.level(in: folder)
        let activity = AgentActivity.read(in: folder)
        if activity != agentActivity { agentActivity = activity }
    }

    private var currentStamp: Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    /// An agent connected with `--mcp` may have saved the journal. Pick its change up before saving over it.
    func reloadIfChangedOnDisk() {
        guard currentStamp != diskStamp else { return }
        reload()
    }

    private func watchForAgentChanges() {
        refreshAgentState()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.reloadIfChangedOnDisk()
                self?.refreshAgentState()
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }
    #endif

    func reload() {
        do {
            #if os(macOS)
            let stamp = currentStamp
            #endif
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                let saved = try JSONDecoder().decode(SavedJournal.self, from: data)
                journal = try Self.validate(saved.journal)
                cloudState = saved.cloud
            }
            #if os(macOS)
            diskStamp = stamp
            #endif
            loadError = nil
        } catch {
            loadError = "Glimmer couldn’t open the journal. The original file is still on this device."
        }
    }

    @discardableResult
    func change(_ mutate: (inout Journal) -> Void) -> Bool {
        do {
            try withWriteLock {
                #if os(macOS)
                // Another MCP client or the app may have committed while this client was waiting.
                reloadIfChangedOnDisk()
                #endif
                guard loadError == nil else { throw CocoaError(.fileReadCorruptFile) }
                var next = journal
                let now = Date()
                // Capture verified dates from pre-ledger journals before an edit replaces the last checklist date.
                if next.readerDays == nil { next.preserveReaderDays(asOf: now) }
                mutate(&next)
                next.preserveReaderDays(asOf: now)
                var nextCloud = cloudState
                if var state = nextCloud {
                    try state.replica.observe(from: journal, to: next, device: state.device)
                    nextCloud = state
                }
                let amount = next.coins - journal.coins
                try persist(next, cloud: nextCloud)
                if amount > 0 {
                    notice = nil
                    earnedCoins = EarnedCoins(amount: amount)
                }
            }
            return true
        } catch {
            notice = "Glimmer couldn’t save this change. Please try again."
            return false
        }
    }

    private func withWriteLock(_ action: () throws -> Void) throws {
        #if os(macOS)
        // The journal file itself is atomically replaced, so coordinate on a stable sibling.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.appending(path: ".journal-write.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno != EINTR { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        }
        #endif
        try action()
    }

    private func save(_ next: Journal, cloud state: JournalCloudState?) throws {
        try withWriteLock {
            #if os(macOS)
            guard currentStamp == diskStamp else {
                reload()
                throw CocoaError(.fileWriteFileExists)
            }
            #endif
            try persist(next, cloud: state)
        }
    }

    private func persist(_ next: Journal, cloud state: JournalCloudState?) throws {
        let data = try JSONEncoder().encode(SavedJournal(journal: next, cloud: state))
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var backupExcludedDirectory = directory
        try backupExcludedDirectory.setResourceValues(values)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        diskStamp = currentStamp
        #endif
        journal = next
        cloudState = state
    }

    func setCloudEnabled(_ enabled: Bool) {
        guard canUseCloud else { return }
        do {
            var state: JournalCloudState
            if let cloudState {
                state = cloudState
            } else {
                let device = UUID()
                state = JournalCloudState(device: device, replica: try JournalReplica(seed: journal, device: device))
            }
            state.enabled = enabled
            state.acceptAccountChange = enabled
            try save(journal, cloud: state)
            cloudGeneration = UUID()
            cloud?.stop()
            cloudStatus = enabled ? "Connecting to iCloud Drive…" : "Sync is off on this device."
        } catch {
            cloudStatus = "Couldn’t change iCloud sync. Try again."
        }
    }

    func syncWhileActive() async {
        while cloudEnabled && !Task.isCancelled {
            await syncNow()
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
        }
    }

    func cloudAccountChanged() {
        cloudGeneration = UUID()
        cloud?.stop()
        if cloudEnabled { cloudStatus = "Checking your Apple Account…" }
    }

    func syncNow() async {
        guard let cloud, cloudEnabled, !syncing, loadError == nil else { return }
        syncing = true
        defer { syncing = false }
        let generation = cloudGeneration
        lastCheck = .now
        syncErrorCode = nil
        do {
            let connection = try await Task.detached { try JournalCloud.connect() }.value
            guard cloudGeneration == generation, cloudEnabled, !Task.isCancelled, var state = cloudState else { return }
            guard let connection else {
                cloud.stop()
                accountStatus = FileManager.default.ubiquityIdentityToken == nil ? "Not signed in" : "iCloud Drive unavailable"
                cloudStatus = "iCloud Drive is unavailable. Your changes are saved here."
                return
            }
            accountStatus = "Connected"
            if state.account != connection.account {
                if state.account != nil && !state.acceptAccountChange {
                    setCloudEnabled(false)
                    cloudStatus = "Apple Account changed. Turn on sync to use the current account."
                    return
                }
                if state.account != nil {
                    state.device = UUID()
                    state.replica = try JournalReplica(seed: journal, device: state.device)
                }
                state.account = connection.account
            }
            if state.acceptAccountChange || state.account != cloudState?.account {
                state.acceptAccountChange = false
                try save(journal, cloud: state)
            }
            guard let files = try cloud.files(in: connection) else {
                cloudStatus = "Looking for your journal in iCloud Drive…"
                return
            }
            let device = state.device
            let exchange = try await Task.detached {
                try JournalCloud.pull(files, device: device, in: connection)
            }.value
            lastCloudContact = .now
            // Read local state again after the download so an edit made while it ran is never lost.
            guard cloudGeneration == generation, cloudEnabled, !Task.isCancelled, var current = cloudState else { return }
            current.replica.merge(exchange.remote)
            if current.replica != cloudState?.replica {
                let updated = try current.replica.materialize(keepingEngagement: journal.engagement)
                try save(updated, cloud: current)
            }
            guard !exchange.downloading else {
                cloudStatus = "Downloading changes from iCloud Drive…"
                return
            }
            let replica = current.replica
            let uploaded = try await Task.detached {
                if exchange.own != replica {
                    return try JournalCloud.push(replica, device: device, in: connection)
                }
                return try JournalCloud.uploaded(device: device, in: connection)
            }.value
            guard cloudGeneration == generation, cloudEnabled else { return }
            cloudStatus = uploaded && replica == cloudState?.replica ? "Journal synced with iCloud Drive." : "Waiting for iCloud Drive to upload changes…"
        } catch {
            let failure = error as NSError
            syncErrorCode = "\(failure.domain) (\(failure.code))"
            if cloudGeneration == generation && cloudEnabled {
                cloudStatus = "iCloud sync will retry. Your changes are saved here."
            }
        }
    }

    func export() throws -> Data { try JSONEncoder().encode(journal) }

    func readBackup(_ url: URL) throws -> Journal {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try Self.decode(Data(contentsOf: url))
    }

    nonisolated static func decode(_ data: Data) throws -> Journal {
        try validate(JSONDecoder().decode(Journal.self, from: data))
    }

    private nonisolated static func validate(_ journal: Journal) throws -> Journal {
        let todos = journal.personalTodos ?? []
        let steps = journal.todoSteps ?? []
        let estimates = journal.todoEstimates ?? []
        guard journal.version == 1,
              Set(steps.map(\.id)).count == steps.count, steps.allSatisfy(\.isValid),
              Set(estimates.map(\.id)).count == estimates.count, estimates.allSatisfy(\.isValid),
              Set(journal.tasks.map(\.id)).count == journal.tasks.count,
              Set(todos.map(\.id)).count == todos.count, todos.allSatisfy(\.isValid),
              Set(journal.moments.map(\.id)).count == journal.moments.count,
              journal.rewards.values.allSatisfy({ (0...60).contains($0) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return journal.droppingBuiltInEmoji()
    }

    func start(name: String) {
        guard let catalog, !journal.onboardingComplete else { return }
        let now = Date()
        change {
            $0.started = now
            $0.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.tasks = catalog.initialTasks.map { PlanTask(template: $0, date: now) }
            $0.award(40, key: "welcome")
            let selected = $0.answers["first_experiment"]?.first
            if let suggestion = catalog.startingSuggestions($0.answers).first(where: { $0.id == selected }) {
                $0.queued.append(suggestion)
            }
        }
    }

    func startOrQueue(_ suggestion: Suggestion) {
        if change({
            if $0.experiment == nil {
                $0.experiment = Experiment(suggestion: suggestion, start: Date())
                $0.queued.removeAll { $0.id == suggestion.id }
            } else if $0.experiment?.suggestion != suggestion && !$0.queued.contains(suggestion) {
                $0.queued.append(suggestion)
            }
        }) {
            notice = journal.experiment?.suggestion == suggestion ? "Experiment started." : "Saved for your next experiment."
        }
    }

    var todayKey: String { CalendarDay.key(day) }
    var todaysTasks: [PlanTask] { journal.tasks.filter { $0.occurs(on: day) } }
    var duePersonalTodos: [PersonalTodo] {
        let today = PracticeDate.key(day)
        return PersonalTodo.ordered((journal.personalTodos ?? []).filter { $0.isDue(by: today) })
    }

    @discardableResult
    func setPersonalTodoDone(_ id: UUID, done: Bool) -> Bool {
        var found = false
        return change { journal in
            found = journal.setPersonalTodo(id, done: done)
        } && found
    }
    var todayLogs: [Moment] { journal.moments.filter { $0.day == todayKey } }
    var todayCompletion: Set<String> { journal.completions[todayKey] ?? [] }
}
