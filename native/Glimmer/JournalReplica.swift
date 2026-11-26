import Foundation

/// Sync independent journal records so offline changes on two devices can both survive.
struct JournalReplica: Codable, Equatable, Sendable {
    struct Key: Codable, Hashable, Sendable {
        let path: [String]
        init(_ components: String...) { path = components }
    }

    struct Stamp: Codable, Equatable, Comparable, Sendable {
        let revision: UInt64
        let device: UUID

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.revision != rhs.revision { return lhs.revision < rhs.revision }
            return lhs.device.uuidString < rhs.device.uuidString
        }
    }

    struct Entry: Codable, Equatable, Sendable {
        let stamp: Stamp
        let insertion: Stamp
        let position: Int
        let data: Data?
    }

    private(set) var entries: [Key: Entry] = [:]

    // Older clients reject unknown fields inside entries. Keep additive fields in a
    // sibling section so those clients can continue to sync every field they understand.
    private enum CodingKeys: String, CodingKey { case entries, readerDayEntries, choreEntries, seasonalEntries, personalTodoEntries, toolkitEntries }
    private static let toolkitFields: Set<String> = ["todoSteps", "todoEstimates"]
    private static let choreFields: Set<String> = ["favoriteChores", "recentChores"]

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        entries = try fields.decode([Key: Entry].self, forKey: .entries)
        let days = try fields.decodeIfPresent([Key: Entry].self, forKey: .readerDayEntries) ?? [:]
        guard days.keys.allSatisfy({ $0.path.first == "readerDays" && $0.path.count == 2 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        entries.merge(days) { _, extensionEntry in extensionEntry }
        let chores = try fields.decodeIfPresent([Key: Entry].self, forKey: .choreEntries) ?? [:]
        guard chores.keys.allSatisfy({
            ($0.path.count == 2 && $0.path[0] == "favoriteChores") ||
            ($0.path.count == 3 && $0.path[0] == "recentChores")
        }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        entries.merge(chores) { _, extensionEntry in extensionEntry }
        let seasonal = try fields.decodeIfPresent([Key: Entry].self, forKey: .seasonalEntries) ?? [:]
        guard seasonal.keys.allSatisfy({ $0.path.first == "seasonalChecks" && $0.path.count == 3 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        entries.merge(seasonal) { _, extensionEntry in extensionEntry }
        let todos = try fields.decodeIfPresent([Key: Entry].self, forKey: .personalTodoEntries) ?? [:]
        guard todos.keys.allSatisfy({ $0.path.first == "personalTodos" && $0.path.count == 2 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        entries.merge(todos) { _, extensionEntry in extensionEntry }
        let toolkit = try fields.decodeIfPresent([Key: Entry].self, forKey: .toolkitEntries) ?? [:]
        guard toolkit.keys.allSatisfy({ $0.path.count == 2 && Self.toolkitFields.contains($0.path[0]) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        entries.merge(toolkit) { _, extensionEntry in extensionEntry }
    }

    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(entries.filter {
            $0.key.path.first != "readerDays" && $0.key.path.first != "seasonalChecks" && $0.key.path.first != "personalTodos"
                && !Self.choreFields.contains($0.key.path.first ?? "") && !Self.toolkitFields.contains($0.key.path.first ?? "")
        }, forKey: .entries)
        let days = entries.filter { $0.key.path.first == "readerDays" }
        if !days.isEmpty { try fields.encode(days, forKey: .readerDayEntries) }
        let chores = entries.filter { Self.choreFields.contains($0.key.path.first ?? "") }
        if !chores.isEmpty { try fields.encode(chores, forKey: .choreEntries) }
        let seasonal = entries.filter { $0.key.path.first == "seasonalChecks" }
        if !seasonal.isEmpty { try fields.encode(seasonal, forKey: .seasonalEntries) }
        let todos = entries.filter { $0.key.path.first == "personalTodos" }
        if !todos.isEmpty { try fields.encode(todos, forKey: .personalTodoEntries) }
        let toolkit = entries.filter { Self.toolkitFields.contains($0.key.path.first ?? "") }
        if !toolkit.isEmpty { try fields.encode(toolkit, forKey: .toolkitEntries) }
    }

    init() {}

    init(seed: Journal, device: UUID) throws {
        try observe(from: Journal(), to: seed, device: device)
    }

    mutating func observe(from old: Journal, to new: Journal, device: UUID) throws {
        let before = try Self.project(old)
        let after = try Self.project(new)
        let revision = entries.values.map(\.stamp.revision).max() ?? 0
        guard revision < UInt64.max else { throw CocoaError(.fileWriteUnknown) }
        let stamp = Stamp(revision: revision + 1, device: device)
        for key in Set(before.keys).union(after.keys) where before[key]?.data != after[key]?.data {
            let existing = entries[key]
            entries[key] = Entry(stamp: stamp, insertion: existing?.insertion ?? stamp,
                                 position: existing?.position ?? after[key]?.position ?? 0, data: after[key]?.data)
        }
    }

    mutating func merge(_ other: Self) {
        entries.merge(other.entries) { local, remote in
            // Retain the earliest known insertion so concurrent edits cannot reorder the list.
            let first = Self.precedes(local, remote) ? local : remote
            let newest: Entry
            if local.stamp != remote.stamp {
                newest = local.stamp < remote.stamp ? remote : local
            } else if let localData = local.data, let remoteData = remote.data {
                newest = localData.lexicographicallyPrecedes(remoteData) ? remote : local
            } else {
                newest = local.data == nil ? local : remote
            }
            return Entry(stamp: newest.stamp, insertion: first.insertion, position: first.position, data: newest.data)
        }
    }

    func materialize(keepingEngagement engagement: Engagement) throws -> Journal {
        var json = try Self.object(Journal())
        var groups: [String: [(Key, Entry)]] = [:]
        for (key, entry) in entries {
            guard let field = key.path.first, Self.schema[field] != nil else { throw CocoaError(.fileReadCorruptFile) }
            groups[field, default: []].append((key, entry))
        }
        for (field, atoms) in groups {
            var live = [(path: [String], value: Any)]()
            for (key, entry) in atoms.sorted(by: {
                if $0.1.insertion != $1.1.insertion || $0.1.position != $1.1.position { return Self.precedes($0.1, $1.1) }
                return $0.0.path.lexicographicallyPrecedes($1.0.path)
            }) {
                guard let data = entry.data else { continue }
                live.append((Array(key.path.dropFirst()), try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)))
            }
            switch Self.schema[field] {
            case .scalar:
                // A deleted scalar returns to its original default, including absent optional fields.
                if let value = live.first?.value { json[field] = value }
            case .records, .members:
                json[field] = live.map(\.value)
            case .dictionary:
                var result: [String: Any] = [:]
                for atom in live where atom.path.count == 1 { result[atom.path[0]] = atom.value }
                json[field] = result
            case .dailyMembership:
                var result: [String: [Any]] = [:]
                for atom in live where atom.path.count == 2 { result[atom.path[0], default: []].append(atom.value) }
                json[field] = result
            case .lessons:
                var lessons: [String: [String: Any]] = [:]
                for atom in live where atom.path.count == 2 || atom.path.count == 3 {
                    var lesson = lessons[atom.path[0]] ?? ["page": 0, "completed": false, "choices": [String: Any]()]
                    if atom.path.count == 3 {
                        var choices = lesson["choices"] as? [String: Any] ?? [:]
                        choices[atom.path[2]] = atom.value
                        lesson["choices"] = choices
                    } else {
                        lesson[atom.path[1]] = atom.value
                    }
                    lessons[atom.path[0]] = lesson
                }
                json[field] = lessons
            case .experiment:
                if var active = live.first(where: { $0.path.isEmpty })?.value as? [String: Any],
                   let id = active["id"] as? String {
                    var checkins: [String: Any] = [:]
                    for atom in live where atom.path.count == 2 && atom.path[0] == id {
                        checkins[atom.path[1]] = atom.value
                    }
                    active["checkins"] = checkins
                    json[field] = active
                }
            case nil: break
            }
        }
        var journal = try JournalStore.decode(try Self.encode(json))
        journal.engagement = engagement
        if journal.coins >= 80 { journal.coffeeUnlocked = true }
        return journal
    }

    private static func precedes(_ lhs: Entry, _ rhs: Entry) -> Bool {
        if lhs.insertion != rhs.insertion { return lhs.insertion < rhs.insertion }
        return lhs.position < rhs.position
    }

    private enum Field {
        case scalar, records(String), members, dictionary, dailyMembership, lessons, experiment
    }

    private static let schema: [String: Field] = [
        "started": .scalar, "name": .scalar, "onboardingIndex": .scalar, "tracker": .scalar,
        "coffeeUnlocked": .scalar, "answers": .dictionary, "energy": .dictionary,
        "moods": .dictionary, "rewards": .dictionary, "challenges": .dictionary, "cleaningLast": .dictionary,
        "tasks": .records("id"), "moments": .records("id"), "history": .records("id"), "queued": .records("title"),
        "personalTodos": .records("id"), "todoSteps": .records("id"), "todoEstimates": .records("id"),
        "readerDays": .members, "favoriteSources": .members, "customSources": .members, "completions": .dailyMembership,
        "favoriteChores": .members, "recentChores": .dailyMembership,
        "seasonalChecks": .dailyMembership,
        "habits": .dailyMembership, "cleaningChecks": .dailyMembership, "lessons": .lessons, "experiment": .experiment
    ]

    private struct Atom {
        let data: Data
        let position: Int
    }

    private static func project(_ journal: Journal) throws -> [Key: Atom] {
        let json = try object(journal)
        var result: [Key: Atom] = [:]
        func add(_ key: Key, _ value: Any, position: Int = 0) throws {
            result[key] = Atom(data: try encode(value), position: position)
        }

        for (field, rule) in schema {
            guard let value = json[field] else { continue }
            switch rule {
            case .scalar:
                try add(Key(field), value)
            case .records(let idField):
                for (position, original) in (value as? [[String: Any]] ?? []).enumerated() {
                    guard let id = original[idField] as? String else { throw CocoaError(.fileReadCorruptFile) }
                    var record = original
                    if let weekdays = record["weekdays"] as? [Int] { record["weekdays"] = weekdays.sorted() }
                    try add(Key(field, id), record, position: position)
                }
            case .members:
                for (position, member) in (value as? [String] ?? []).enumerated() {
                    try add(Key(field, member), member, position: position)
                }
            case .dictionary:
                for (key, item) in value as? [String: Any] ?? [:] { try add(Key(field, key), item) }
            case .dailyMembership:
                for (day, items) in value as? [String: [Any]] ?? [:] {
                    for item in items { try add(Key(field, day, try encode(item).base64EncodedString()), item) }
                }
            case .lessons:
                for (id, lesson) in value as? [String: [String: Any]] ?? [:] {
                    if let page = lesson["page"] as? Int, page != 0 { try add(Key(field, id, "page"), page) }
                    if lesson["completed"] as? Bool == true { try add(Key(field, id, "completed"), true) }
                    for (question, choice) in lesson["choices"] as? [String: Any] ?? [:] {
                        try add(Key(field, id, "choices", question), choice)
                    }
                }
            case .experiment:
                guard var active = value as? [String: Any], let id = active["id"] as? String else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let checkins = active.removeValue(forKey: "checkins") as? [String: Any] ?? [:]
                try add(Key(field), active)
                for (day, outcome) in checkins { try add(Key(field, id, day), outcome) }
            }
        }
        return result
    }

    private static func object(_ journal: Journal) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return json
    }

    private static func encode(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
    }
}
