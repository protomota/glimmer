import Foundation

/// The suggested questions on Coach's welcome screen. Coach shows three, each from a different category,
/// and never repeats one from the set shown last time. Add prompts here; keep them short, warm and in the
/// person's own voice.
struct CoachPrompt: Hashable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case reflect, practice, read, focus, rest, stillness, kindness

        /// Practice topics the rule-based guide prefers for this kind of question.
        var topics: Set<String> {
            switch self {
            case .reflect: ["everyday_reflection"]
            case .practice: []
            case .read: ["learn_build"]
            case .focus: ["protect_attention", "everyday_agency"]
            case .rest: ["rest"]
            case .stillness: ["stillness_spirit"]
            case .kindness: ["rest", "everyday_reflection", "work_growth"]
            }
        }

        /// Words in a typed question that point to this category, checked in `CoachPrompts.category(for:)`.
        var keywords: Set<String> {
            switch self {
            case .reflect: ["week", "logged", "moments", "pattern", "patterns", "noticed", "notice", "stood", "reflect", "looking"]
            case .practice: ["practice", "habit", "exercise", "small", "try", "something"]
            case .read: ["read", "reading", "lesson", "learn", "learning", "study", "book"]
            case .focus: ["focus", "plan", "planning", "priority", "priorities", "distracted", "scattered", "start", "first", "task", "tasks", "today's"]
            case .rest: ["tired", "energy", "rest", "drained", "sleep", "exhausted", "break", "recharge", "restore", "worn"]
            case .stillness: ["still", "stillness", "quiet", "silence", "pray", "prayer", "spirit", "spiritual", "meditate", "grateful", "gratitude", "peace", "calm", "sacred", "slow"]
            case .kindness: ["stuck", "overwhelmed", "behind", "failing", "failed", "guilty", "guilt", "kind", "kinder", "myself", "shame", "messed", "hard", "harsh", "enough"]
            }
        }

        /// The rule-based guide's opening line when no AI route is available.
        var guideLead: String {
            switch self {
            case .reflect: "A pattern starts with one honest moment."
            case .practice: "Here’s one small practice to try today. Keep it only if it helps."
            case .read: "Here’s something to learn from today."
            case .focus: "Pick the one thing that matters most today and give it your first clear half hour. This can help."
            case .rest: "Rest counts as part of the work. Here’s a gentle way to choose it on purpose."
            case .stillness: "A few quiet minutes are enough. Try this when you find a pause."
            case .kindness: "Being stuck isn’t a verdict on you. Make the next step smaller, then try this."
            }
        }
    }

    let text: String
    let category: Category
}

enum CoachPrompts {
    /// The fixed set UI tests rely on, used whenever Glimmer runs against a test journal.
    static let fixed = [
        CoachPrompt(text: "What stood out this week?", category: .reflect),
        CoachPrompt(text: "Help me choose one small practice", category: .practice),
        CoachPrompt(text: "What should I read today?", category: .read),
    ]

    static let pool: [CoachPrompt] = [
        // Reflection
        .init(text: "What stood out this week?", category: .reflect),
        .init(text: "What gave me energy lately?", category: .reflect),
        .init(text: "What’s been draining me without my noticing?", category: .reflect),
        .init(text: "What pattern do you see in my week?", category: .reflect),
        .init(text: "What am I avoiding, and why?", category: .reflect),
        .init(text: "What went better than I expected?", category: .reflect),
        .init(text: "Help me look back on today", category: .reflect),
        // Choosing a small practice
        .init(text: "Help me choose one small practice", category: .practice),
        .init(text: "Give me something small to try today", category: .practice),
        .init(text: "What’s a five-minute practice for right now?", category: .practice),
        .init(text: "Suggest a practice for a busy day", category: .practice),
        .init(text: "What could I try instead of scrolling?", category: .practice),
        .init(text: "Help me build one tiny habit", category: .practice),
        .init(text: "What’s one small way to help someone today?", category: .practice),
        // What to read or learn
        .init(text: "What should I read today?", category: .read),
        .init(text: "Give me one idea to think about today", category: .read),
        .init(text: "What lesson fits where I am right now?", category: .read),
        .init(text: "What’s worth learning this week?", category: .read),
        .init(text: "Teach me something in five minutes", category: .read),
        .init(text: "What should I study when my mind won’t settle?", category: .read),
        .init(text: "Recommend something to read before bed", category: .read),
        // Focus and planning today
        .init(text: "Help me plan a gentle day", category: .focus),
        .init(text: "What should I focus on first?", category: .focus),
        .init(text: "My mind is scattered. Where do I start?", category: .focus),
        .init(text: "Help me pick today’s one priority", category: .focus),
        .init(text: "How do I start a task I keep putting off?", category: .focus),
        .init(text: "Help me protect my focus this afternoon", category: .focus),
        .init(text: "What can I let go of today?", category: .focus),
        // Energy and rest
        .init(text: "I’m tired. What would actually help?", category: .rest),
        .init(text: "How can I rest without feeling guilty?", category: .rest),
        .init(text: "What restores me versus what just passes time?", category: .rest),
        .init(text: "Help me take a real break", category: .rest),
        .init(text: "My energy is low. What’s a kind next step?", category: .rest),
        .init(text: "How do I wind down tonight?", category: .rest),
        .init(text: "What’s one way to recharge in ten minutes?", category: .rest),
        // Stillness and spirit
        .init(text: "Help me find a quiet moment today", category: .stillness),
        .init(text: "Give me a short practice of stillness", category: .stillness),
        .init(text: "What can I be grateful for right now?", category: .stillness),
        .init(text: "Help me slow down and notice", category: .stillness),
        .init(text: "What question could I carry through today?", category: .stillness),
        .init(text: "How do I make room for silence?", category: .stillness),
        .init(text: "Help me feel some peace today", category: .stillness),
        // Self-kindness when stuck
        .init(text: "I feel stuck. Can you help?", category: .kindness),
        .init(text: "I’m behind on everything. Where do I begin?", category: .kindness),
        .init(text: "Help me be kinder to myself today", category: .kindness),
        .init(text: "I messed up. What now?", category: .kindness),
        .init(text: "I feel overwhelmed. What’s one small step?", category: .kindness),
        .init(text: "How do I stop being so hard on myself?", category: .kindness),
        .init(text: "Remind me that today is enough", category: .kindness),
    ]

    /// Three prompts from three different categories, none of them in `previous`.
    static func draw(excluding previous: Set<String>, using generator: inout some RandomNumberGenerator) -> [CoachPrompt] {
        let categories = CoachPrompt.Category.allCases.shuffled(using: &generator)
        var picked: [CoachPrompt] = []
        for category in categories where picked.count < 3 {
            let options = pool.filter { $0.category == category && !previous.contains($0.text) }
            if let prompt = options.randomElement(using: &generator) { picked.append(prompt) }
        }
        return picked
    }

    static func draw(excluding previous: Set<String>) -> [CoachPrompt] {
        var generator = SystemRandomNumberGenerator()
        return draw(excluding: previous, using: &generator)
    }

    /// The category of a question: an exact pooled prompt, or the first category whose keywords it uses.
    static func category(for question: String) -> CoachPrompt.Category? {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = pool.first(where: { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }) { return match.category }
        let words = Set(trimmed.lowercased().replacingOccurrences(of: "’", with: "'")
            .split { !$0.isLetter && $0 != "'" }.map(String.init))
        let order: [CoachPrompt.Category] = [.read, .reflect, .kindness, .rest, .stillness, .focus, .practice]
        return order.first { !words.isDisjoint(with: $0.keywords) }
    }
}
