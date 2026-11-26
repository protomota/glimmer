import Foundation

enum CalendarDay {
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    static func distance(_ start: Date, _ end: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}

enum Decision: String, CaseIterable, Codable, Identifiable {
    case less, same, more
    var id: Self { self }
    var title: String { ["Less", "Same", "More"][Self.allCases.firstIndex(of: self) ?? 0] }
}

enum Cadence: String, CaseIterable, Codable, Identifiable {
    case daily = "Daily", weekly = "Weekly", monthly = "Monthly"
    var id: Self { self }
}

enum Tracker: String, CaseIterable, Codable, Identifiable {
    case checklist = "Checklist", ring = "Ring"
    var id: Self { self }
}

struct PlanTask: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    /// An SF Symbol name. Older tasks may hold an emoji, which Glyph shows as its symbol.
    var icon = ""
    var name = ""
    var category = "custom"
    var anchor = Date()
    var repeats = true
    var cadence: Cadence = .daily
    var every = 1
    var weekdays: Set<Int> = []

    init() {}

    init(template: TaskTemplate, category: String? = nil, date: Date) {
        id = template.id
        icon = template.icon
        name = template.name
        self.category = category ?? template.cat ?? "custom"
        anchor = date
        repeats = template.freq != "Once"
        cadence = template.freq == "Weekly" ? .weekly : template.freq == "Monthly" ? .monthly : .daily
    }

    var coins: Int {
        ["easy": 5, "focus": 15, "move": 10, "wind": 10, "offline": 15, "calm": 5][category] ?? 10
    }

    var schedule: String {
        if !repeats { return anchor.formatted(.dateTime.month(.abbreviated).day()) }
        if every <= 1 { return cadence.rawValue }
        let unit = cadence == .daily ? "days" : cadence == .weekly ? "weeks" : "months"
        return "Every \(every) \(unit)"
    }

    func occurs(on date: Date, calendar: Calendar = .current) -> Bool {
        let days = CalendarDay.distance(anchor, date, calendar: calendar)
        guard days >= 0 else { return false }
        if !repeats { return days == 0 }
        let interval = max(1, every)
        switch cadence {
        case .daily:
            return days.isMultiple(of: interval)
        case .weekly:
            guard let start = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start,
                  let end = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return false }
            let week = CalendarDay.distance(start, end, calendar: calendar) / 7
            let weekday = calendar.component(.weekday, from: date)
            let valid = weekdays.isEmpty ? [calendar.component(.weekday, from: anchor)] : Array(weekdays)
            return week.isMultiple(of: interval) && valid.contains(weekday)
        case .monthly:
            guard let start = calendar.dateInterval(of: .month, for: anchor)?.start,
                  let end = calendar.dateInterval(of: .month, for: date)?.start,
                  let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count else { return false }
            let months = calendar.dateComponents([.month], from: start, to: end).month ?? 0
            let target = min(calendar.component(.day, from: anchor), daysInMonth)
            return months.isMultiple(of: interval) && calendar.component(.day, from: date) == target
        }
    }
}

struct PersonalTodo: Codable, Identifiable, Equatable {
    static let titleLimit = 160
    let id: UUID
    var title: String
    var dueDay: String?
    var reminderAt: Date?
    var completed = false

    init(id: UUID = UUID(), title: String = "", dueDay: String? = nil, reminderAt: Date? = nil) {
        self.id = id
        self.title = title
        self.dueDay = dueDay
        self.reminderAt = reminderAt
    }

    var isValid: Bool {
        (1...Self.titleLimit).contains(title.trimmingCharacters(in: .whitespacesAndNewlines).count)
            && (dueDay.map { PracticeDate.parse($0) != nil } ?? true)
            && (reminderAt?.timeIntervalSinceReferenceDate.isFinite ?? true)
    }

    func isDue(by day: String) -> Bool {
        !completed && (dueDay.map { $0 <= day } ?? false)
    }

    static func ordered(_ tasks: [Self]) -> [Self] {
        tasks.sorted { ($0.dueDay ?? "~") < ($1.dueDay ?? "~") }
    }
}

/// One step of a personal to-do. Steps are their own records so edits to different steps on two
/// devices both survive a sync, and older app versions that don't know steps can't erase them.
struct TodoStep: Codable, Identifiable, Equatable {
    static let titleLimit = 160
    /// A step can be broken down once more. Deeper levels are not stored.
    static let maxLevels = 2
    let id: UUID
    let todoID: UUID
    var parentID: UUID?
    var title: String
    var done = false
    var order: Double

    init(id: UUID = UUID(), todoID: UUID, parentID: UUID? = nil, title: String, done: Bool = false, order: Double) {
        self.id = id
        self.todoID = todoID
        self.parentID = parentID
        self.title = title
        self.done = done
        self.order = order
    }

    var isValid: Bool {
        (1...Self.titleLimit).contains(title.trimmingCharacters(in: .whitespacesAndNewlines).count) && order.isFinite
    }
}

/// A time estimate for a personal to-do, keyed by the to-do's ID.
struct TodoEstimate: Codable, Identifiable, Equatable {
    static let range = 1...1440
    /// The to-do this estimate belongs to.
    let id: UUID
    var minutes: Int
    /// Where the estimate came from: `ToolkitSource` raw values, or "person" when typed by hand.
    var source: String

    var isValid: Bool { Self.range.contains(minutes) && !source.isEmpty && source.count <= 40 }
}

struct Moment: Codable, Identifiable, Hashable {
    static let words = ["Drained", "Off", "Neutral", "Lighter", "Nourished"]
    var id = UUID()
    var source: String
    var kind: String
    var tags: [String]
    var value: Double
    var decision: Decision
    var date: Date
    var day: String
    var score: Int { Self.step(value) - 2 }
    var word: String { Self.words[Self.step(value)] }

    static func step(_ value: Double) -> Int {
        Int((min(1, max(0, value.isFinite ? value : 0.5)) * 4).rounded())
    }

    /// The general category a source belongs to. Summaries group by this, never by the source itself.
    static func kind(of source: String, catalog: Catalog) -> String {
        let name = source.lowercased()
        if catalog.activities.contains(source) { return "Activity" }
        if catalog.people.contains(source) { return "People" }
        if ["chatgpt", "claude", "gemini", "perplexity", "copilot"].contains(where: { name.contains($0) }) { return "AI" }
        if ["slack", "discord", "whatsapp", "telegram", "messages"].contains(where: { name.contains($0) }) { return "Messages" }
        if ["vs code", "xcode", "github", "figma"].contains(where: { name.contains($0) }) { return "Work" }
        if ["netflix", "twitch", "disney", "hulu"].contains(where: { name.contains($0) }) { return "Streaming" }
        if ["news", "podcast"].contains(where: { name.contains($0) }) { return "News" }
        return "Feed"
    }
}

struct EnergyCheck: Codable {
    let level: String
    let value: Double
}

struct ChallengeRecord: Codable {
    let choice: String
    let date: Date
    var feedback: String?
}

struct LessonRecord: Codable {
    var page = 0
    var choices: [String: String] = [:]
    var completed = false
}

struct Experiment: Codable, Identifiable {
    enum Outcome: String, CaseIterable, Codable, Identifiable {
        case held = "Held it", slip = "Slipped a bit"
        var id: Self { self }
    }

    enum Review: String, CaseIterable, Codable, Identifiable {
        case keep = "Keep it", adjust = "Adjust it", drop = "Drop it"
        var id: Self { self }
    }

    var id = UUID()
    var suggestion: Suggestion
    var start: Date
    var checkins: [String: Outcome] = [:]
    var review: Review?
    let duration = 7

    enum CodingKeys: String, CodingKey { case id, suggestion, start, checkins, review }
    var readyToReview: Bool { checkins.count >= duration }
}

struct Engagement: Codable {
    var count = 0
    var requestedReview = false
    var actions: Set<String> = []
    var shouldRequestReview: Bool { count >= 5 && !requestedReview && !actions.contains("review") }
}

struct Journal: Codable {
    var version = 1
    var started: Date?
    var name = ""
    var answers: [String: [String]] = [:]
    var onboardingIndex = 0
    var tracker: Tracker = .checklist
    var tasks: [PlanTask] = []
    // Optional for journals and backup files written before personal to-dos existed.
    var personalTodos: [PersonalTodo]?
    // Toolkit details for personal to-dos. Optional so older journals and backups still load.
    var todoSteps: [TodoStep]?
    var todoEstimates: [TodoEstimate]?
    var completions: [String: Set<String>] = [:]
    var rewards: [String: Int] = [:]
    var moments: [Moment] = []
    var customSources: [String] = []
    /// Starred apps, activities and people. Optional so journals saved before favourites existed still load.
    var favoriteSources: [String]?
    var energy: [String: EnergyCheck] = [:]
    var challenges: [String: ChallengeRecord] = [:]
    var coffeeUnlocked = false
    var habits: [String: Set<String>] = [:]
    var moods: [String: Int] = [:]
    var cleaningChecks: [String: Set<Int>] = [:]
    var cleaningLast: [String: String] = [:]
    var favoriteChores: Set<String>?
    var recentChores: [String: Set<String>]?
    var seasonalChecks: [String: Set<String>]?
    var lessons: [String: LessonRecord] = [:]
    /// Actual days of personal practice, retained as older checklist and activity records change.
    var readerDays: Set<String>?
    var experiment: Experiment?
    var history: [Experiment] = []
    var queued: [Suggestion] = []
    var engagement = Engagement()

    var coins: Int { rewards.values.reduce(0, +) }
    var onboardingComplete: Bool { started != nil }

    mutating func toggleSeasonalCheck(_ item: String, in checklist: String) {
        var checks = seasonalChecks ?? [:]
        if checks[checklist, default: []].remove(item) == nil { checks[checklist, default: []].insert(item) }
        seasonalChecks = checks
    }

    mutating func toggleFavoriteChore(_ id: String) {
        var favorites = favoriteChores ?? []
        if favorites.remove(id) == nil { favorites.insert(id) }
        favoriteChores = favorites
    }

    mutating func toggleCleaningChore(_ list: CleaningList, at index: Int, on date: Date) {
        let id = list.choreID(at: index)
        let day = CalendarDay.key(date)
        if cleaningChecks[list.id, default: []].remove(index) != nil {
            recentChores?[id]?.remove(day)
            return
        }
        cleaningChecks[list.id, default: []].insert(index)
        var recent = recentChores ?? [:]
        recent[id, default: []].insert(day)
        recentChores = recent
        if cleaningChecks[list.id]?.count == list.items.count {
            cleaningLast[list.id] = day
        }
    }

    mutating func toggleMaintenanceChore(_ id: String, on date: Date) {
        let day = CalendarDay.key(date)
        var recent = recentChores ?? [:]
        if recent[id, default: []].remove(day) == nil { recent[id, default: []].insert(day) }
        recentChores = recent
    }

    func activeReaderDays(asOf date: Date) -> Set<String> {
        var days = readerDays ?? []
        days.formUnion(moments.map(\.day))
        days.formUnion(energy.keys)
        days.formUnion(moods.keys)
        days.formUnion(cleaningLast.values)
        for (day, tasks) in completions where !tasks.isEmpty { days.insert(day) }
        for dates in habits.values { days.formUnion(dates) }
        for challenge in challenges.values { days.insert(PracticeDate.key(challenge.date)) }
        for experiment in history + [experiment].compactMap({ $0 }) {
            days.insert(PracticeDate.key(experiment.start))
            days.formUnion(experiment.checkins.keys)
        }
        let latest = PracticeDate.key(date)
        return days.filter { $0 <= latest && PracticeDate.parse($0) != nil }
    }

    mutating func preserveReaderDays(asOf date: Date) {
        let observed = activeReaderDays(asOf: date)
        if !observed.isEmpty { readerDays = observed }
    }

    mutating func award(_ amount: Int, key: String) {
        if rewards[key] == nil { rewards[key] = amount }
        if coins >= 80 { coffeeUnlocked = true }
    }

    func planDay(on date: Date) -> Int {
        max(1, CalendarDay.distance(started ?? date, date) + 1)
    }

    func lessonIsOpen(_ number: Int, on date: Date) -> Bool {
        planDay(on: date) >= number
    }

    mutating func toggleTask(_ task: PlanTask, on date: Date) {
        let day = CalendarDay.key(date)
        let key = "task:\(day):\(task.id)"
        if completions[day, default: []].remove(task.id) != nil {
            rewards.removeValue(forKey: key)
        } else {
            completions[day, default: []].insert(task.id)
            award(task.coins, key: key)
        }
    }

    /// Checks a habit on or off for a day. The first check-off of a habit on a day earns coins, so the
    /// coin celebration plays; unchecking takes them back.
    mutating func toggleHabit(_ id: String, on date: Date) {
        let day = CalendarDay.key(date)
        let key = "habit:\(day):\(id)"
        if habits[id, default: []].remove(day) != nil {
            rewards.removeValue(forKey: key)
        } else {
            habits[id, default: []].insert(day)
            award(5, key: key)
        }
    }

    /// Marks a personal to-do done or open. Finishing one earns coins once; reopening takes them back.
    mutating func setPersonalTodo(_ id: UUID, done: Bool) -> Bool {
        guard let index = personalTodos?.firstIndex(where: { $0.id == id }) else { return false }
        personalTodos?[index].completed = done
        let key = "todo:\(id.uuidString)"
        if done { award(5, key: key) } else { rewards.removeValue(forKey: key) }
        return true
    }

    mutating func record(_ moment: Moment) {
        guard !moments.contains(where: { $0.id == moment.id }) else { return }
        moments.append(moment)
        award(10, key: "log:\(moment.day)")
        engagement.count += 1
    }

    mutating func recordEnergy(_ check: EnergyCheck, on date: Date) {
        let key = CalendarDay.key(date)
        energy[key] = check
        award(5, key: "energy:\(key)")
    }

    mutating func completeChallenge(_ challenge: Challenge, choice: String, on date: Date) {
        guard challenges[challenge.id] == nil else { return }
        challenges[challenge.id] = ChallengeRecord(choice: choice, date: date)
        award(challenge.coins, key: "challenge:\(challenge.id)")
    }

    mutating func completeLesson(_ lesson: Lesson, on date: Date) {
        guard lessonIsOpen(lesson.number, on: date), lessons[lesson.id]?.completed != true else { return }
        lessons[lesson.id, default: LessonRecord()].completed = true
        readerDays = (readerDays ?? []).union([PracticeDate.key(date)])
        award(15, key: "lesson:\(lesson.id)")
    }

    mutating func checkIn(_ outcome: Experiment.Outcome, on date: Date) {
        guard let active = experiment, !active.readyToReview, date >= Calendar.current.startOfDay(for: active.start) else { return }
        let day = CalendarDay.key(date)
        guard active.checkins[day] == nil else { return }
        experiment?.checkins[day] = outcome
    }

    mutating func reviewExperiment(_ review: Experiment.Review, on date: Date) {
        guard var active = experiment, active.readyToReview else { return }
        active.review = review
        history.append(active)
        experiment = nil
        award(60, key: "experiment:\(active.id)")
        if review == .adjust {
            let suggestion = Suggestion(type: "Adjustment", title: active.suggestion.title,
                                        sub: "Try a smaller version of this experiment for another week.")
            experiment = Experiment(suggestion: suggestion, start: date)
        }
    }
}

// MARK: - To-do steps and estimates

extension Journal {
    /// Steps directly under a to-do (parent nil) or under one step, in their saved order.
    func steps(for todoID: UUID, parent: UUID? = nil) -> [TodoStep] {
        (todoSteps ?? []).filter { $0.todoID == todoID && $0.parentID == parent }
            .sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) }
    }

    /// Every step of a to-do in reading order: each step followed by its own smaller steps.
    func flatSteps(for todoID: UUID) -> [TodoStep] {
        steps(for: todoID).flatMap { [$0] + steps(for: todoID, parent: $0.id) }
    }

    /// The step to work on now: the first unfinished step, or its first unfinished smaller step.
    func nextStep(for todoID: UUID, skipping skipped: Set<UUID> = []) -> TodoStep? {
        for step in steps(for: todoID) where !step.done && !skipped.contains(step.id) {
            let children = steps(for: todoID, parent: step.id).filter { !$0.done && !skipped.contains($0.id) }
            return children.first ?? step
        }
        return nil
    }

    func estimate(for todoID: UUID) -> TodoEstimate? {
        todoEstimates?.first { $0.id == todoID }
    }

    /// Replaces the steps at one level. Smaller steps of removed steps go with them.
    mutating func replaceSteps(for todoID: UUID, parent: UUID? = nil, with titles: [String]) {
        let clean = titles.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(TodoStep.titleLimit)) }
            .filter { !$0.isEmpty }
        let old = steps(for: todoID, parent: parent)
        let removed = Set(old.map(\.id))
        var all = (todoSteps ?? []).filter { !removed.contains($0.id) && !removed.contains($0.parentID ?? UUID()) }
        for (index, title) in clean.enumerated() {
            // Keep a step's identity and done state when its text is unchanged.
            if let kept = old.first(where: { $0.title == title && !all.contains($0) }) {
                var step = kept
                step.order = Double(index)
                all.append(step)
                all += (todoSteps ?? []).filter { $0.parentID == kept.id }
            } else {
                all.append(TodoStep(todoID: todoID, parentID: parent, title: title, order: Double(index)))
            }
        }
        todoSteps = all
    }

    mutating func setStepDone(_ id: UUID, done: Bool) {
        guard let index = todoSteps?.firstIndex(where: { $0.id == id }) else { return }
        todoSteps?[index].done = done
        // Finishing a step finishes its smaller steps too.
        guard done, let step = todoSteps?[index] else { return }
        for child in steps(for: step.todoID, parent: step.id) where !child.done { setStepDone(child.id, done: true) }
        // Finishing the last smaller step finishes the step it belongs to.
        if let parent = step.parentID, steps(for: step.todoID, parent: parent).allSatisfy(\.done),
           todoSteps?.first(where: { $0.id == parent })?.done == false {
            setStepDone(parent, done: true)
        }
    }

    mutating func setEstimate(_ minutes: Int?, source: String, for todoID: UUID) {
        var estimates = (todoEstimates ?? []).filter { $0.id != todoID }
        if let minutes { estimates.append(TodoEstimate(id: todoID, minutes: min(max(minutes, 1), 1440), source: source)) }
        todoEstimates = estimates
    }

    /// Removes a to-do with its steps and estimate.
    mutating func removePersonalTodo(_ id: UUID) {
        personalTodos?.removeAll { $0.id == id }
        todoSteps?.removeAll { $0.todoID == id }
        todoEstimates?.removeAll { $0.id == id }
    }
}

extension Journal {
    /// Built-in activity and people names that carried an emoji before 1.1.4.
    static let emojiBuiltInNames: Set<String> = [
        "🚶 Walk", "🏋️ Workout", "🍳 Cooked", "📖 Read", "🎮 Gaming", "🧹 Tidied up", "🎧 Music", "🛌 Rested", "🧘 Meditated", "🤸 Stretched", "🌳 Time outside", "😴 Napped", "✍️ Journaled", "🎨 Made something", "🎸 Played music", "🎙️ Podcast", "📚 Studied", "💻 Deep work", "🛒 Errands", "🚿 Shower", "☕ Coffee break", "🌱 Gardened", "📞 Called a friend", "💛 Time with partner", "🍽️ Family dinner", "💬 Coworker chat", "👋 Saw a friend", "🎉 Group hangout"
    ]

    /// Renames moments and favourites logged under an older emoji built-in name, such as "💻 Deep work",
    /// to the plain name the catalog now uses. Names people typed themselves are left as they wrote them.
    func droppingBuiltInEmoji() -> Journal {
        func plain(_ name: String) -> String { Self.emojiBuiltInNames.contains(name) ? Glyph.plainName(name) : name }
        var journal = self
        for index in journal.moments.indices { journal.moments[index].source = plain(journal.moments[index].source) }
        if let favorites = journal.favoriteSources {
            var seen = Set<String>()
            journal.favoriteSources = favorites.map(plain).filter { seen.insert($0).inserted }
        }
        return journal
    }
}
