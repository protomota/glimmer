import Foundation

struct ReflectionSummary {
    struct Group: Identifiable {
        let name: String
        let moments: [Moment]
        var id: String { name }
        var count: Int { moments.count }
        var average: Double { Double(moments.reduce(0) { $0 + $1.score }) / Double(count) }
        var commonTags: [String] { ReflectionSummary.tagGroups(moments).prefix(3).map(\.name) }
    }

    let moments: [Moment]
    let day: Date
    let days: Int

    init(_ logs: [Moment], day: Date, days: Int) {
        self.day = day
        self.days = days
        let first = Calendar.current.date(byAdding: .day, value: 1 - days, to: day) ?? day
        let bounds = CalendarDay.key(first)...CalendarDay.key(day)
        moments = logs.filter { bounds.contains($0.day) }.sorted { $0.date > $1.date }
    }

    var alignment: Int? {
        guard !moments.isEmpty else { return nil }
        return Int((100 * Double(moments.filter { $0.score >= 0 }.count) / Double(moments.count)).rounded())
    }

    var sources: [Group] { Self.groups(moments, by: \.source) }
    var kinds: [Group] { Self.groups(moments, by: \.kind) }
    var daily: [Group] { Self.groups(moments, by: \.day).sorted { $0.name < $1.name } }
    var best: [Group] { sources.filter { $0.average > 0 }.sorted { $0.average > $1.average } }
    var rough: [Group] { sources.filter { $0.average < 0 }.sorted { $0.average < $1.average } }

    var hasHistory: Bool { moments.count >= 5 && daily.count >= 3 }

    var takeaway: String {
        if let only = moments.first, moments.count == 1 {
            return "\(only.source) left you feeling \(only.word.lowercased())."
        }
        if !hasHistory && !moments.isEmpty {
            return "\(moments.count) moments recorded across \(daily.count) \(daily.count == 1 ? "day" : "days")."
        }
        if let lift = best.first, let drain = rough.first {
            return "\(lift.name) averaged higher than \(drain.name) in this window. Try noticing what’s different about those moments."
        }
        if let lift = best.first {
            return "\(lift.name) tended to leave you feeling lighter in the moments you logged."
        }
        if let drain = rough.first {
            return "\(drain.name) tended to leave you feeling more drained. You could notice the next time you reach for it."
        }
        return moments.isEmpty ? "A few moments are enough to begin seeing a pattern." : "Your recent logs sit near neutral. Different times or tags may tell you more."
    }

    func suggestions(catalog: Catalog, answers: [String: [String]], level: Int = 1) -> [Suggestion] {
        var suggestions: [Suggestion] = catalog.suggestions(level: level, goals: answers["primary_goal"] ?? [])
        if let drain = rough.first {
            suggestions.append(.init(type: "Boundary", title: "Pause before opening \(drain.name)",
                                     sub: "For a week, ask what you’re hoping to get from it and log how it lands."))
        }
        if let lift = best.first, let drain = rough.first {
            suggestions.append(.init(type: "Swap", title: "Choose \(lift.name) before \(drain.name) once",
                                     sub: "Try this when both are available, then compare how you feel."))
        }
        suggestions += catalog.startingSuggestions(answers)
        return Array(suggestions.prefix(4))
    }

    static func tagGroups(_ logs: [Moment]) -> [Group] {
        var tags: [String: [Moment]] = [:]
        for log in logs {
            for tag in Set(log.tags) { tags[tag, default: []].append(log) }
        }
        return sorted(tags)
    }

    private static func groups(_ logs: [Moment], by key: KeyPath<Moment, String>) -> [Group] {
        sorted(Dictionary(grouping: logs) { $0[keyPath: key] })
    }

    private static func sorted(_ dictionary: [String: [Moment]]) -> [Group] {
        dictionary.map { Group(name: $0.key, moments: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }
}
