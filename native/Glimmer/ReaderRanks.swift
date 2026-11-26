import SwiftUI

enum ReaderRank: String, CaseIterable, Identifiable {
    case fledgling = "Fledgling", seeker = "Seeker", scholar = "Scholar", sage = "Sage", guru = "Guru"
    var id: Self { self }
    var bird: String {
        switch self {
        case .fledgling: "Chick"
        case .seeker: "Swallow"
        case .scholar: "Heron"
        case .sage: "Crane"
        case .guru: "Owl"
        }
    }
    var requiredDays: Int {
        switch self {
        case .fledgling: 0
        case .seeker: 14
        case .scholar: 30
        case .sage: 60
        case .guru: 90
        }
    }

    /// What this rank opens. Content deepens with practice days, never with pressure.
    var opens: String {
        switch self {
        case .fledgling: "Tiny wins, the first practices and the reading plan"
        case .seeker: "Steady steps join your daily suggestions: practices and challenges that ask a little more"
        case .scholar: "Deeper water joins your daily suggestions: patterns, values and what you avoid"
        case .sage: "Wide circles join your daily suggestions: relationships, repair and community"
        case .guru: "Quiet mastery joins your daily suggestions: stillness, conscience and a practice of your own"
        }
    }

    var requirement: String {
        switch self {
        case .fledgling: "Yours from day one"
        case .guru: "90 active days and 90 lessons"
        default: "\(requiredDays) active days"
        }
    }
}

/// Glimmer's coaching content opens in five stages that follow the reader ranks'
/// active-day thresholds. A stage is about practice days, not lessons or coins.
enum JourneyStage {
    static let count = ReaderRank.allCases.count

    static func level(days: Int) -> Int {
        max(1, ReaderRank.allCases.filter { days >= $0.requiredDays }.count)
    }

    static func rank(for level: Int) -> ReaderRank {
        ReaderRank.allCases[min(max(level, 1), count) - 1]
    }

    /// The short name of each stage's content, used for section headings.
    static func name(_ level: Int) -> String {
        switch min(max(level, 1), count) {
        case 1: "Tiny wins"
        case 2: "Steady steps"
        case 3: "Deeper water"
        case 4: "Wide circles"
        default: "Quiet mastery"
        }
    }

    /// What a stage's practices and challenges ask of a person. Everything stays open:
    /// ranks only set what Glimmer recommends, so these notes describe, never gate.
    static func asks(_ level: Int) -> String {
        switch min(max(level, 1), count) {
        case 1: "Asks for a few minutes"
        case 2: "Asks for a little steadiness"
        case 3: "Asks for honest reflection"
        case 4: "Asks for a real conversation or a kind boundary"
        default: "Asks for quiet and your own direction"
        }
    }

    /// A gentle label for content deeper than Glimmer's current recommendations.
    static func aheadNote(_ level: Int) -> String { "\(name(level)) · \(asks(level).lowercased())" }
}

extension Journal {
    func journeyLevel(asOf date: Date) -> Int {
        JourneyStage.level(days: activeReaderDays(asOf: date).count)
    }

    /// The level for today's recommendations. Growth isn't a straight line, so a low or
    /// empty energy check today brings the daily suggestions back to gentle ground.
    func guidanceLevel(asOf date: Date) -> Int {
        let level = journeyLevel(asOf: date)
        guard let check = energy[CalendarDay.key(date)], ["empty", "low"].contains(check.level) else { return level }
        return min(level, 2)
    }
}

struct ReaderProgress {
    static let curriculumLength = 90
    let completed: Int
    let days: Int
    var total: Int { Self.curriculumLength }
    var rank: ReaderRank { ReaderRank.allCases.last(where: hasEarned) ?? .fledgling }
    var next: ReaderRank? { ReaderRank.allCases.first { !hasEarned($0) } }

    init(journal: Journal, catalog: Catalog, asOf date: Date = .now) {
        days = journal.activeReaderDays(asOf: date).count
        let course = catalog.lessons.filter { (1...Self.curriculumLength).contains($0.number) }
        completed = Set(course.filter { journal.lessons[$0.id]?.completed == true }.map(\.number)).count
    }

    func hasEarned(_ rank: ReaderRank) -> Bool {
        days >= rank.requiredDays && (rank != .guru || completed == total)
    }

    func remaining(until rank: ReaderRank) -> String {
        var steps = [String]()
        let daysLeft = rank.requiredDays - days
        if daysLeft > 0 { steps.append("\(daysLeft) more active \(daysLeft == 1 ? "day" : "days")") }
        let lessonsLeft = total - completed
        if rank == .guru && lessonsLeft > 0 {
            steps.append("\(lessonsLeft) more \(lessonsLeft == 1 ? "lesson" : "lessons")")
        }
        return steps.joined(separator: " and ") + " to unlock " + rank.rawValue + "."
    }

    var summary: String { "\(days) active \(days == 1 ? "day" : "days") · \(completed) of \(total) lessons" }
}

struct ReaderBird: View {
    let rank: ReaderRank
    var unlocked = true
    var size: CGFloat = 48
    @Environment(\.readingTheme) private var theme
    @Environment(\.colorSchemeContrast) private var contrast

    private var opticalOffset: CGSize {
        switch rank {
        case .fledgling:
            // Align the rendered SVG's silhouette with the center of the badge.
            CGSize(width: -size * 0.015, height: size * 0.002)
        case .sage: CGSize(width: size * 0.03, height: size * 0.02)
        default: .zero
        }
    }

    var body: some View {
        let moss = Color(light: "42624D", dark: "A8C5A8")
        let isGuru = rank == .guru
        let field = isGuru ? Color(light: "304B40", dark: "C0CFA9") : moss
        let fineLine = contrast == .increased ? 1.5 : 1.0
        ZStack {
            Circle().fill(unlocked ? field : .clear)
            if !unlocked {
                Circle().strokeBorder(moss.opacity(contrast == .increased ? 0.8 : 0.46), lineWidth: fineLine)
            }
            if isGuru && size > 24 {
                Circle().inset(by: size * 0.065)
                    .strokeBorder(unlocked ? theme.surface.opacity(0.7) : moss.opacity(0.55),
                                  lineWidth: max(fineLine, size * 0.021))
            }
            Image(isGuru && (size <= 24 || !unlocked) ? "RankGuruCompact" : "Rank" + rank.rawValue)
                .resizable().scaledToFit()
                .foregroundStyle(unlocked ? theme.surface : moss.opacity(contrast == .increased ? 0.85 : 0.65))
                .padding(size * (isGuru ? (size <= 24 ? 0.165 : 0.21) : 0.19))
                .offset(opticalOffset)
        }
        .frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct ReaderRankBar: View {
    let progress: ReaderProgress
    let coins: Int
    var body: some View {
        NavigationLink {
            ReaderRanksView(progress: progress, coins: coins)
        } label: {
            HStack(spacing: 12) {
                ReaderBird(rank: progress.rank, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.rank.rawValue).font(.headline)
                    Text(progress.summary).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                CoinCount(count: coins)
                Text("coins").font(.callout)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reader ranks. \(progress.rank.rawValue), \(progress.summary), \(coins) coins")
        .accessibilityIdentifier("readerRanks")
    }
}

struct ReaderRanksView: View {
    let progress: ReaderProgress
    let coins: Int
    var body: some View {
        Page(title: "Your reader ranks", subtitle: "Your practice adds up. Days away simply pause your progress.", width: 600) {
            Panel {
                HStack(spacing: 16) {
                    ReaderBird(rank: progress.rank, size: 68)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(progress.rank.rawValue).font(GlimmerFont.reading(.title, weight: .medium))
                        Text(progress.summary).font(.callout)
                    }
                }
                if let next = progress.next {
                    Text(progress.remaining(until: next))
                        .foregroundStyle(.secondary)
                } else {
                    Text("You’ve earned all five birds.").foregroundStyle(.secondary)
                }
            }
            Text("Each rank brings deeper practices and challenges into what Glimmer suggests. Everything stays open to explore anytime, and low-energy days bring gentler ideas. Completing a lesson or task, checking in, logging a moment, or trying a habit, challenge, cleaning list or experiment counts. Each calendar day counts once.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(ReaderRank.allCases) { rank in
                let earned = progress.hasEarned(rank)
                HStack(spacing: 14) {
                    ReaderBird(rank: rank, unlocked: earned)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(rank.rawValue).font(.headline)
                        Text("\(rank.bird) · \(rank.requirement)").font(.callout).foregroundStyle(.secondary)
                        Text(rank.opens).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Image(systemName: earned ? "checkmark.circle.fill" : "lock")
                        .foregroundStyle(earned ? GlimmerColor.sage : .secondary).accessibilityLabel(earned ? "Unlocked" : "Locked")
                }.accessibilityElement(children: .combine)
                if rank != .guru { Divider() }
            }
        }
    }
}
