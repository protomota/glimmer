import Foundation

struct Catalog: Decodable {
    let sources: [String]
    // Built-in names are plain words; any emoji in an older or remote edition is dropped (see Glyph).
    @PlainNames var activities: [String]
    @PlainNames var people: [String]
    let tags: [String: [String]]
    let defaultTags: [String]
    let initialTasks: [TaskTemplate]
    let library: [TaskCategory]
    let preload: [TaskTemplate]
    let onboarding: [OnboardingStep]
    let challenges: [Challenge]
    let energy: [EnergyLevel]
    let energyMessages: [String: String]
    let habits: [Habit]
    let cleaning: CleaningCatalog
    let seasonal: [SeasonalEdition]?
    let quotes: [DailyQuote]?
    let coach: [Suggestion]
    let startingPractices: [String: Suggestion]
    let practiceTopics: [PracticeTopic]
    let praise: [String]
    let lessons: [Lesson]

    static func load(from url: URL) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func startingSuggestions(_ answers: [String: [String]]) -> [Suggestion] {
        let distractions = answers["distraction"] ?? []
        let ai = answers["ai_use"] ?? []
        let replacements = answers["replacements"] ?? []
        let topics = (answers["primary_goal"] ?? []).compactMap { goal in practiceTopics.first { $0.id == goal } }
        // Give each selected topic a place before offering a second practice from one topic.
        var suggestions: [Suggestion] = []
        func add(_ key: String) {
            if let suggestion = startingPractices[key] { suggestions.append(suggestion) }
        }
        for round in 0..<3 {
            suggestions += topics.compactMap { topic -> Suggestion? in
                let opening = topic.exercises.filter { $0.stage == 1 }
                return opening.indices.contains(round) ? opening[round].suggestion : nil
            }
        }
        if !Set(distractions).isDisjoint(with: ["outrage", "feeds"]) {
            suggestions.append(contentsOf: coach.prefix(2))
        }
        if distractions.contains("short_video") {
            add("short_video")
        }
        if !ai.isEmpty && !ai.contains("rare") {
            add("ai_quiz")
        }
        if replacements.contains("walk") {
            add("change_of_scene")
        }
        if replacements.contains("friend") {
            add("contact_someone")
        }
        add("notice_feed")
        add("screen_free_meal")
        return Array(suggestions.prefix(4))
    }
}

/// A list of names decoded without leading or trailing emoji, so "💻 Deep work" reads "Deep work".
@propertyWrapper
struct PlainNames: Decodable {
    var wrappedValue: [String]

    init(wrappedValue: [String]) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
        wrappedValue = try decoder.singleValueContainer().decode([String].self).map(Glyph.plainName)
    }
}

struct DailyQuote: Decodable, Identifiable {
    let id: String
    let text: String
    let author: String

    private static let firstDay = DateComponents(year: 2026, month: 11, day: 23)

    static func quote(on date: Date, from quotes: [DailyQuote]) -> DailyQuote? {
        let calendar = PracticeDate.calendar
        guard !quotes.isEmpty, let start = calendar.date(from: firstDay) else { return nil }
        let offset = CalendarDay.distance(start, date, calendar: calendar)
        let index = (offset % quotes.count + quotes.count) % quotes.count
        return quotes[index]
    }
}

struct TaskTemplate: Decodable, Identifiable {
    let icon: String
    let name: String
    let freq: String
    let cat: String?
    var id: String {
        "lt_" + name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

struct TaskCategory: Decodable, Identifiable {
    let id: String
    let icon: String
    let name: String
    let desc: String
    let tasks: [TaskTemplate]
}

struct OnboardingStep: Decodable {
    struct Option: Decodable, Identifiable {
        let v: String
        let label: String
        var id: String { v }
    }

    let kind: String
    let key: String?
    let mode: String?
    let max: Int?
    let kicker: String?
    let title: String?
    let sub: String?
    let options: [Option]?

    func toggling(_ value: String, in answers: [String]) -> [String] {
        if mode == "single" { return [value] }
        if answers.contains(value) { return answers.filter { $0 != value } }
        if let max, answers.count >= max { return answers }
        return answers + [value]
    }

}

struct PracticeTopic: Decodable, Identifiable {
    let id: String
    let title: String
    let exercises: [Practice]
}

/// Editorial identifiers remain stable when the displayed copy changes.
struct Practice: Decodable, Identifiable {
    let id: String
    let title: String
    let sub: String
    let type: String
    /// Journey stage (1–5) at which this practice opens. Missing means stage 1.
    let level: Int?
    var stage: Int { min(max(level ?? 1, 1), JourneyStage.count) }
    var suggestion: Suggestion { .init(type: type, title: title, sub: sub) }

    func taskID(day: String) -> String { "glimmer:practice:\(day):\(id)" }

    func task(on date: Date) -> PlanTask {
        var task = PlanTask()
        task.id = taskID(day: PracticeDate.key(date))
        task.name = title
        task.icon = "leaf.fill"
        task.repeats = false
        task.anchor = date
        return task
    }
}

struct Suggestion: Codable, Identifiable, Hashable {
    let type: String
    let title: String
    let sub: String
    var id: String { title }
}

struct Challenge: Decodable, Identifiable {
    struct Page: Decodable {
        let title: String
        let lines: [String]
        let hero: String?
        let heroAlt: String?
    }

    struct Option: Decodable, Identifiable {
        let e: String
        let l: String
        var id: String { l }
    }

    let id: String
    let icon: String
    let title: String
    let sub: String
    let coins: Int
    let mins: Int
    /// Journey stage (1–5) at which this challenge opens. Missing means stage 1.
    let level: Int?
    var stage: Int { min(max(level ?? 1, 1), JourneyStage.count) }
    let hero: String?
    let heroAlt: String?
    let teach: [Page]
    let q: String
    let opts: [Option]
    let action: Page
    let done: Page
}

struct EnergyLevel: Decodable, Identifiable {
    let id: String
    let label: String
    let color: String
}

struct Habit: Decodable, Identifiable {
    let id: String
    let icon: String
    let name: String
}

struct CleaningCatalog: Decodable {
    let speed: [CleaningList]
    let daily: CleaningList
    let rooms: [CleaningList]
    let maintenance: [MaintenanceChore]?
}

struct MaintenanceChore: Decodable, Identifiable {
    let id: String
    let room: String
    let title: String
    let cadence: String
    let tip: String
}

struct CleaningList: Decodable, Identifiable {
    let id: String
    let title: String?
    let mins: Int?
    let sub: String?
    let items: [String]
    var name: String { title ?? "\(mins ?? 0)-minute clean" }

    func choreID(at index: Int) -> String { "cleaning:\(id):\(items[index])" }
}

struct SeasonalEdition: Decodable, Identifiable {
    struct Tip: Decodable, Identifiable {
        let id: String
        let title: String
        let summary: String
        let body: String
    }

    struct Checklist: Decodable, Identifiable {
        struct Item: Decodable, Identifiable {
            let id: String
            let title: String
            let detail: String
        }

        let id: String
        let title: String
        let summary: String
        let items: [Item]
    }

    struct Resource: Decodable, Identifiable {
        let title: String
        let url: URL
        var id: URL { url }
    }

    let id: String
    let title: String
    let summary: String
    let start: String
    let end: String
    let tips: [Tip]
    let maintenance: [String]
    let checklists: [Checklist]
    let resources: [Resource]?

    func isFeatured(on date: Date) -> Bool {
        let day = String(PracticeDate.key(date).suffix(5))
        if start <= end { return (start...end).contains(day) }
        return day >= start || day <= end
    }

    func recommendation(on date: Date) -> (list: Checklist, item: Checklist.Item)? {
        guard isFeatured(on: date) else { return nil }
        let recommendations = checklists.flatMap { list in list.items.map { (list, $0) } }
        guard !recommendations.isEmpty else { return nil }
        let calendar = PracticeDate.calendar
        let year = calendar.component(.year, from: date)
        let seasonYear = start > end && String(PracticeDate.key(date).suffix(5)) < start ? year - 1 : year
        guard let first = PracticeDate.parse("\(seasonYear)-" + start) else { return nil }
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: first),
                                             to: calendar.startOfDay(for: date)).day ?? 0
        return recommendations[offset % recommendations.count]
    }

    func progressKey(for checklist: Checklist, on date: Date) -> String {
        let key = PracticeDate.key(date)
        let year = Int(key.prefix(4)) ?? PracticeDate.calendar.component(.year, from: date)
        let seasonYear = start > end && String(key.suffix(5)) < start ? year - 1 : year
        return "\(id)/\(seasonYear)/\(checklist.id)"
    }
}

struct Lesson: Decodable, Identifiable {
    struct Page: Decodable {
        let kind: String
        let emoji: String
        let title: String
        let body: String?
        let question: String?
        let options: [String]?
        let tryToday: String?
    }

    let slug: String
    let number: Int
    let arc: String
    let title: String
    let tagline: String
    let minutes: Int
    let hero: String?
    let heroAlt: String?
    let pages: [Page]
    var id: String { slug }
}

/// A dashboard key uses the Mac's local Gregorian date, independent of display language.
enum PracticeDate {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .current
        return value
    }
    static func key(_ date: Date) -> String { CalendarDay.key(date, calendar: calendar) }
    static func parse(_ value: String) -> Date? {
        guard value.utf8.count == 10 else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              key(date) == value else { return nil }
        return date
    }
}

extension Catalog {
    static let reflectionTopicID = "everyday_reflection"

    var reflectionTopic: PracticeTopic? {
        practiceTopics.first { $0.id == Self.reflectionTopicID }
    }

    func dailyReflection(on date: Date, level: Int = JourneyStage.count) -> Practice? {
        guard let exercises = reflectionTopic?.exercises.filter({ $0.stage <= level }), !exercises.isEmpty else { return nil }
        return Self.stagePick(exercises, stage: \.stage, level: level, day: dayIndex(date))
    }

    /// Picks from content that is open at this level. Two days in three come from the
    /// current or previous stage, so the daily guidance deepens as the person does.
    static func stagePick<T>(_ open: [T], stage: (T) -> Int, level: Int, day: Int) -> T? {
        guard !open.isEmpty else { return nil }
        let fresh = open.filter { stage($0) >= max(1, level - 1) }
        // Each pool counts only its own days, so both rotate through every item.
        if fresh.isEmpty || day % 3 == 2 { return open[(day / 3) % open.count] }
        return fresh[((day / 3) * 2 + day % 3) % fresh.count]
    }

    private func dayIndex(_ date: Date) -> Int {
        PracticeDate.calendar.ordinality(of: .day, in: .era, for: date) ?? 1
    }

    func dailyPractice(on date: Date, level: Int = JourneyStage.count) -> (topic: PracticeTopic, practice: Practice)? {
        let choices = practiceTopics.filter { $0.id != Self.reflectionTopicID }
            .flatMap { topic in topic.exercises.filter { $0.stage <= level }.map { (topic, $0) } }
        return Self.stagePick(choices, stage: { $0.1.stage }, level: level, day: dayIndex(date))
    }

    /// Up to two practices from the person's current stage, from their chosen topics first.
    func suggestions(level: Int, goals: [String]) -> [Suggestion] {
        guard level > 1 else { return [] }
        let ordered = practiceTopics.filter { goals.contains($0.id) } + practiceTopics.filter { !goals.contains($0.id) }
        let matching = ordered.flatMap { $0.exercises.filter { [level, level - 1].contains($0.stage) && $0.stage > 1 } }
        return Array(matching.prefix(2).map(\.suggestion))
    }

    /// The challenge to offer next: an unfinished one at the person's current stage first,
    /// then the earliest unfinished one that is open.
    func nextChallenge(for journal: Journal, level: Int) -> Challenge? {
        let open = challenges.filter {
            journal.challenges[$0.id] == nil && $0.stage <= level && ($0.id != "coffee" || journal.coffeeUnlocked)
        }
        return open.first { $0.stage == level } ?? open.first
    }

    func dailyLesson(for journal: Journal, on date: Date) -> Lesson? {
        guard !lessons.isEmpty else { return nil }
        return lessons[(journal.planDay(on: date) - 1) % lessons.count]
    }
}

/// Shared native and MCP attribution for Glimmer's editorial guidance.
enum CoachingSource {
    static let author = "Brad Dunlap"
    static let role = "author and life coach"
    static let credit = "\(author), \(role)"
    static let sourcesURL = URL(string: "https://glimmertoday.ai/support#coaching-sources")!
    static let note = "I created Glimmer to share what I’ve learned from lived experience, my research and writing, and the people I’ve learned from along the way. Some exercises draw on published research. Other exercises and spiritual reflections come from my own perspective. These are ideas you can try and judge for yourself. Choose what fits your life. I’m not a doctor. Glimmer offers general life guidance and doesn’t provide medical advice, diagnosis, or treatment."
}
