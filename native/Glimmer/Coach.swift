import FoundationModels
import SwiftUI

/// A colored badge for an average aftertaste between -2 and +2.
struct ScoreBadge: View {
    let average: Double

    var body: some View {
        Text(Moment.words[min(4, max(0, Int(average.rounded()) + 2))]).font(.subheadline.monospacedDigit().weight(.bold))
            .foregroundStyle(average >= 0 ? GlimmerColor.sage : GlimmerColor.ember)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background((average >= 0 ? GlimmerColor.sage : GlimmerColor.ember).opacity(0.13), in: .capsule)
            .accessibilityLabel("Average \(score(average))")
    }
}

struct InsightsView: View {
    @State private var logging = false
    @Environment(JournalStore.self) private var store
    let catalog: Catalog

    var body: some View {
        let summary = ReflectionSummary(store.journal.moments, day: store.day, days: 14)
        Page(title: "Insights", subtitle: "Built from the moments you chose to log.", width: 940) {
            if summary.hasHistory {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        AftertasteTally(summary: summary).frame(minWidth: 400)
                        mix(summary).frame(minWidth: 220)
                    }
                    VStack(spacing: 16) { AftertasteTally(summary: summary); mix(summary) }
                }
            } else {
                Panel(padding: 20) {
                    GlyphTile("leaf.fill", tint: GlimmerColor.sage, size: 44)
                    Text(summary.moments.isEmpty ? "What stayed with you today?" : summary.moments.count == 1 ? "Your first moment" : "Your week is taking shape")
                        .font(GlimmerFont.reading(.title, weight: .medium))
                    if !summary.moments.isEmpty { Text(summary.takeaway) }
                    Text("Log moments on different days to see what changes.").foregroundStyle(.secondary)
                    Button("Log a moment") { logging = true }.glimmerButton()
                }
            }
            if !summary.moments.isEmpty {
                Panel(title: "How each activity felt") {
                    ForEach(summary.sources) { group in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(ReflectionSummary.tagGroups(group.moments)) { tag in
                                    HStack { Text(tag.name); Spacer(); ScoreBadge(average: tag.average) }.font(.callout)
                                }
                                if let active = store.journal.experiment, active.suggestion.title.localizedCaseInsensitiveContains(group.name) {
                                    Label("Now trying: \(active.suggestion.title)", systemImage: "flask")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            HStack(spacing: 12) {
                                let kind = group.moments.first?.kind
                                GlyphTile(Glyph.symbol(name: group.name, category: kind), tint: Glyph.tint(for: kind))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Glyph.plainName(group.name)).font(.headline)
                                    Text(([String("\(group.count) logged")] + group.commonTags).joined(separator: " · "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                ScoreBadge(average: group.average)
                            }
                        }
                        if group.id != summary.sources.last?.id { Divider() }
                    }
                }
                Panel(title: "Today’s logs", accent: GlimmerColor.ember) {
                    ForEach(summary.moments.filter { $0.day == store.todayKey }) { moment in
                        HStack(alignment: .top, spacing: 12) {
                            GlyphTile(Glyph.symbol(name: moment.source, category: moment.kind), tint: Glyph.tint(for: moment.kind))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Glyph.plainName(moment.source)).font(.headline)
                                Text(([moment.date.formatted(date: .omitted, time: .shortened)] + moment.tags).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(moment.word).font(.subheadline.weight(.semibold))
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if store.todayLogs.isEmpty { Text("Nothing logged today yet.").foregroundStyle(.secondary) }
                }
            }
        }
        .sheet(isPresented: $logging) { MomentFlow(catalog: catalog).tallSheet() }
    }

    private func mix(_ summary: ReflectionSummary) -> some View {
        Panel(title: "Mix of inputs", accent: GlimmerColor.honey) {
            let total = Double(max(1, summary.moments.count))
            ForEach(summary.kinds.sorted { $0.count > $1.count }) { group in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(group.name).font(.callout.weight(.medium))
                        Spacer()
                        Text("\(group.count) of \(summary.moments.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Meter(value: Double(group.count) / total, tint: GlimmerColor.honey)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct AftertasteTally: View {
    let summary: ReflectionSummary

    var body: some View {
        let better = summary.moments.filter { $0.score > 0 }
        let neutral = summary.moments.filter { $0.score == 0 }
        let worse = summary.moments.filter { $0.score < 0 }
        Panel(title: "How your moments felt", accent: GlimmerColor.accent) {
            Text(headline(better: better.count, neutral: neutral.count, worse: worse.count))
                .font(GlimmerFont.reading(.title2, weight: .medium))
            VStack(spacing: 12) {
                row("Felt better", moments: better, tint: GlimmerColor.sage)
                row("Felt the same", moments: neutral, tint: .secondary)
                row("Felt worse", moments: worse, tint: GlimmerColor.ember)
            }
            .padding(.vertical, 4)

            if !better.isEmpty || !worse.isEmpty {
                Label("Each block is one moment. Outlined blocks show milder feelings.", systemImage: "square")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let lift = summary.best.first(where: { $0.count >= 3 }),
               let drain = summary.rough.first(where: { $0.count >= 3 }) {
                Divider()
                Text("\(lift.name) felt better \(lift.moments.filter { $0.score > 0 }.count) of \(lift.count) times. \(drain.name) felt worse \(drain.moments.filter { $0.score < 0 }.count) of \(drain.count) times.")
                    .font(.callout)
            }
            Text("\(summary.moments.count) moments across \(summary.daily.count) of the last \(summary.days) days")
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("insights.aftertasteTally")
    }

    private func headline(better: Int, neutral: Int, worse: Int) -> String {
        let half = summary.moments.count / 2
        if better > half { return "Most moments left you feeling better." }
        if neutral > half { return "Most moments left you feeling the same." }
        if worse > half { return "Most moments left you feeling worse." }
        if better > worse + 1 { return "More moments lifted you than drained you." }
        if worse > better + 1 { return "More moments drained you than lifted you." }
        return "Your moments felt mixed."
    }

    private func row(_ title: String, moments: [Moment], tint: Color) -> some View {
        let strong = moments.filter { abs($0.score) == 2 }.count
        let neutral = moments.first?.score == 0
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.callout.weight(.semibold))
                Spacer()
                Text(moments.count.formatted()).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            if moments.isEmpty {
                Capsule().fill(.quaternary).frame(width: 24, height: 2)
                    .frame(height: 12)
                    .accessibilityHidden(true)
            } else {
                FlowLayout(spacing: 3) {
                    ForEach(0..<moments.count, id: \.self) { index in
                        let block = RoundedRectangle(cornerRadius: 2)
                        Group {
                            if index < strong || neutral {
                                block.fill(tint).frame(height: neutral ? 6 : 12)
                            } else {
                                block.strokeBorder(tint, lineWidth: 1.5)
                            }
                        }
                        .frame(width: 14, height: 12)
                    }
                }
                .modifier(ChartReveal())
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(strong == 0 ? "\(moments.count)" : "\(moments.count), \(strong) strongly")
    }
}

struct WeeklyView: View {
    @State private var logging = false
    @Environment(JournalStore.self) private var store
    let catalog: Catalog

    var body: some View {
        let summary = ReflectionSummary(store.journal.moments, day: store.day, days: 7)
        Page(title: "Your week in moments", kicker: "Last seven days", width: 900) {
            if summary.moments.isEmpty {
                Panel(padding: 24) {
                    GlyphTile("leaf.fill", tint: GlimmerColor.sage, size: 48)
                    Text("What’s one moment you remember this week?").font(GlimmerFont.reading(.title))
                    Text("A walk, a conversation, a few minutes to yourself. Write down how it felt.")
                    Button("Log a moment") { logging = true }.glimmerButton(.prominent)
                }
            } else {
                if !summary.best.isEmpty { group("What felt lighter", summary.best, empty: "", tint: GlimmerColor.sage) }
                if !summary.rough.isEmpty { group("What took energy", summary.rough, empty: "", tint: GlimmerColor.ember) }
            }
            LinkRow(title: "Compare with Apple Screen Time", detail: "Estimate one app’s weekly total, then check the same device.", icon: "hourglass", tint: GlimmerColor.dusk) { ScreenTimeCheck() }
                .accessibilityIdentifier("weekly.screenTime")
            if !summary.moments.isEmpty {
            Panel(title: "Your week", accent: GlimmerColor.dusk) {
                Text(summary.takeaway).font(GlimmerFont.display(.title3)).fixedSize(horizontal: false, vertical: true)
                LocalCoachReflection(summary: summary, tone: store.journal.answers["coach_style"]?.first)
            }
            }
            DisclosureGroup("Explore an experiment") {
                VStack(spacing: 8) {
                    ForEach(summary.suggestions(catalog: catalog, answers: store.journal.answers, level: store.journal.guidanceLevel(asOf: store.day))) { suggestion in
                        ActionRow(title: suggestion.title, detail: suggestion.sub, icon: "flask", tint: GlimmerColor.ember,
                                  trailing: "plus.circle") { store.startOrQueue(suggestion) }
                    }
                }
                .glassGroup(spacing: 8)
            }
            let alternatives = summary.best.filter { $0.moments.contains { ["Activity", "People"].contains($0.kind) } }
            if !alternatives.isEmpty {
                group("Real-world inputs that worked", alternatives, empty: "", tint: GlimmerColor.sage)
            }
        }
        .sheet(isPresented: $logging) { MomentFlow(catalog: catalog).tallSheet() }
    }

    private func group(_ title: String, _ groups: [ReflectionSummary.Group], empty: String, tint: Color) -> some View {
        Panel(title: title, accent: tint) {
            if groups.isEmpty { Text(empty).foregroundStyle(.secondary) }
            ForEach(Array(groups.prefix(3))) { group in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name).font(.headline)
                        Text("\(group.count) logged").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    ScoreBadge(average: group.average)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct CoachLibrary: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let catalog: Catalog
    @State private var proposing = false
    @State private var watching = false
    @State private var practiceExpanded = false

    var body: some View {
        let summary = ReflectionSummary(store.journal.moments, day: store.day, days: 14)
        Page(title: "Coach", width: 680) {
            DailyReflectionPanel(catalog: catalog)
            practiceDisclosure
            if let experiment = store.journal.experiment { experimentPanel(experiment) }
            DisclosureGroup("About this guidance") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(CoachingSource.credit).font(.headline)
                    Text(CoachingSource.note).fixedSize(horizontal: false, vertical: true)
                    Link("Explore Glimmer’s coaching sources", destination: CoachingSource.sourcesURL)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }
            .accessibilityIdentifier("coach.author")
            Panel(title: "What I’m noticing", accent: GlimmerColor.ember, padding: 20) {
                HStack(alignment: .top, spacing: 14) {
                    Text(summary.takeaway).font(GlimmerFont.display(.title3)).fixedSize(horizontal: false, vertical: true)
                }
                LocalCoachReflection(summary: summary, tone: store.journal.answers["coach_style"]?.first)
                if !proposing {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { coachActions }
                            .fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 8) { coachActions }
                        }
                    .glassGroup(spacing: 8)
                }
            }
            if !store.journal.queued.isEmpty || proposing {
                Panel(title: "Small experiments", accent: GlimmerColor.ember, plain: true) {
                    let choices = store.journal.queued + (proposing ? summary.suggestions(catalog: catalog, answers: store.journal.answers, level: store.journal.guidanceLevel(asOf: store.day)) : [])
                    let unique = choices.reduce(into: [Suggestion]()) { if !$0.map(\.id).contains($1.id) { $0.append($1) } }
                    VStack(spacing: 8) {
                        ForEach(unique) { suggestion in
                            ActionRow(title: suggestion.title, detail: suggestion.sub, icon: "flask", tint: GlimmerColor.ember,
                                      trailing: "plus.circle") { store.startOrQueue(suggestion) }
                        }
                    }
                    .glassGroup(spacing: 8)
                }
            }
            Panel(title: "Keep it small", accent: GlimmerColor.honey, plain: true) {
                VStack(spacing: 8) {
                    if let tiny = catalog.nextChallenge(for: store.journal, level: store.journal.guidanceLevel(asOf: store.day)) {
                        LinkRow(title: tiny.title, detail: "\(JourneyStage.name(tiny.stage)) · \(tiny.mins) min", icon: "sparkles",
                                tint: GlimmerColor.honey) { ChallengeView(challenge: tiny) }
                    }
                    LinkRow(title: "All challenges", icon: "square.grid.2x2", tint: GlimmerColor.honey) { ChallengesView(catalog: catalog) }
                    LinkRow(title: "Open habits", icon: "leaf", tint: GlimmerColor.sage) { HabitsView(catalog: catalog) }
                }
                .glassGroup(spacing: 8)
            }
        }
    }

    private var practiceDisclosure: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                practiceExpanded.toggle()
            } label: {
                HStack {
                    Text("More ways to practice").font(.headline)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(practiceExpanded ? 90 : 0))
                        .animation(reduceMotion ? nil : .smooth(duration: 0.20), value: practiceExpanded)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coach.practiceDisclosure")
            .accessibilityValue(practiceExpanded ? "Expanded" : "Collapsed")

            ReadingDisclosure(expanded: practiceExpanded) { visible in
                VStack(alignment: .leading, spacing: 10) { practiceOptions(visible: visible) }
            }
        }
    }

    @ViewBuilder private func practiceOptions(visible: Bool) -> some View {
        if let attention = catalog.practiceTopics.first(where: { $0.id == "protect_attention" }),
           let signal = attention.exercises.first(where: { $0.id == "try-an-80-20-day" }) {
            LinkRow(title: signal.title, detail: "Make time for what matters today.", icon: "clock", tint: GlimmerColor.sage) {
                Page(title: signal.title, kicker: attention.title, width: 680) {
                    Panel {
                        Text(signal.sub).fixedSize(horizontal: false, vertical: true)
                        SavePracticeButton(practice: signal)
                    }
                }
            }
            .accessibilityIdentifier("coach.signal")
            .modifier(DisclosureRowMotion(index: 0, count: 4, visible: visible))
        }
        if let daily = catalog.dailyPractice(on: store.day, level: store.journal.guidanceLevel(asOf: store.day)) {
            Panel(title: "Daily Glimmer", accent: GlimmerColor.sage) {
                Text(daily.practice.title).font(GlimmerFont.display(.title3, weight: .bold))
                Text(daily.practice.sub).fixedSize(horizontal: false, vertical: true)
                SavePracticeButton(practice: daily.practice)
                if let lesson = catalog.dailyLesson(for: store.journal, on: store.day) {
                    LinkRow(title: lesson.title, detail: "Today’s lesson", icon: "book", tint: GlimmerColor.sage) { LessonReader(lesson: lesson) }
                }
            }
            .modifier(DisclosureRowMotion(index: 1, count: 4, visible: visible))
        }
        LinkRow(title: "Practice exercises", detail: "Short exercises for work, hands-on learning, and real rest.", icon: "figure.walk.motion", tint: GlimmerColor.sage) {
            PracticeView(topics: catalog.practiceTopics)
        }
        .accessibilityIdentifier("coach.practice")
        .modifier(DisclosureRowMotion(index: 2, count: 4, visible: visible))
        if let community = catalog.practiceTopics.first(where: { $0.id == "community_service" }) {
            LinkRow(title: community.title, detail: "Offer time or a skill to a school, library, or neighbor.", icon: "person.2", tint: GlimmerColor.sage) {
                PracticeView(topics: [community], title: community.title)
            }
            .accessibilityIdentifier("coach.community")
            .modifier(DisclosureRowMotion(index: 3, count: 4, visible: visible))
        }
    }

    @ViewBuilder private var coachActions: some View {
        coachAction("Design it together", icon: "flask") {
            proposing = true
            watching = false
        }
        if !watching {
            coachAction("Keep watching", icon: "eye") {
                watching = true
                store.notice = "Okay. Keep noticing for now."
            }
        }
    }

    private func coachAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .glimmerButton()
        .controlSize(.regular)
    }

    private func experimentPanel(_ experiment: Experiment) -> some View {
        Panel(title: "Experiment · \(experiment.checkins.count) of 7 check-ins", accent: GlimmerColor.ember, padding: 20) {
            Text(experiment.suggestion.title).font(GlimmerFont.display(.title2, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                let held = experiment.checkins.values.filter { $0 == .held }.count
                ForEach(0..<7, id: \.self) { index in
                    Capsule().fill(index < experiment.checkins.count
                                   ? (index < held ? GlimmerColor.sage : GlimmerColor.honey)
                                   : Color.primary.opacity(0.10))
                        .frame(height: 8)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(experiment.checkins.count) of 7 check-ins")
            if experiment.readyToReview {
                LinkRow(title: "Start the review", detail: "Decide whether to keep, adjust or drop it",
                        icon: "text.badge.checkmark", tint: GlimmerColor.ember) { ExperimentReview(experiment: experiment) }
            } else if let result = experiment.checkins[store.todayKey] {
                Label(result == .held ? "Nice. That’s another check-in." : "Noticing the slip is useful. Thanks for checking in.",
                      systemImage: result == .held ? "checkmark.circle" : "leaf")
                    .foregroundStyle(.secondary)
            } else {
                Text("How did it go today?").font(.headline)
                HStack(spacing: 10) {
                    ForEach(Experiment.Outcome.allCases) { outcome in
                        Button(outcome.rawValue, systemImage: outcome == .held ? "checkmark" : "arrow.uturn.backward") {
                            store.change { $0.checkIn(outcome, on: store.day) }
                        }
                        .glimmerButton(.standard)
                        .buttonBorderShape(.capsule).controlSize(.large)
                    }
                }
                .glassGroup(spacing: 10)
            }
        }
    }
}

struct DailyReflectionPanel: View {
    @Environment(JournalStore.self) private var store
    let catalog: Catalog

    var body: some View {
        if let topic = catalog.reflectionTopic, let practice = catalog.dailyReflection(on: store.day, level: store.journal.guidanceLevel(asOf: store.day)) {
            Panel(padding: 22) {
                HStack(spacing: 10) {
                    GlimmerLogo(size: 36)
                    Eyebrow("Today’s reflection")
                }.readingArrival()
                Text(practice.title).font(GlimmerFont.reading(.title, weight: .medium))
                Text(practice.sub).fixedSize(horizontal: false, vertical: true)
                SavePracticeButton(practice: practice)
                NavigationLink("Explore all reflections") {
                    PracticeView(topics: [topic], title: topic.title)
                }
                .glimmerButton()
                .accessibilityIdentifier("coach.reflections")
            }
        }
    }
}

struct SavePracticeButton: View {
    @Environment(JournalStore.self) private var store
    let practice: Practice
    var showSavedStatus = false

    var body: some View {
        let task = practice.task(on: store.day)
        let saved = store.journal.tasks.contains { $0.id == task.id }
        if saved && showSavedStatus {
            Label("Saved to today’s plan", systemImage: "checkmark.circle")
                .font(.callout.weight(.medium))
                .accessibilityIdentifier("coach.practiceSaved")
        } else {
            Button(saved ? "Saved to today’s plan" : "Add to today’s plan") {
                store.change { journal in
                    if !journal.tasks.contains(where: { $0.id == task.id }) { journal.tasks.append(task) }
                }
            }
            .glimmerButton(.prominent)
            .disabled(saved)
            .completionLight(saved, outline: Capsule())
            .accessibilityIdentifier("coach.save." + practice.id)
        }
    }
}

struct PracticeView: View {
    @Environment(JournalStore.self) private var store
    let topics: [PracticeTopic]
    var title = "Practice exercises"

    var body: some View {
        let level = store.journal.journeyLevel(asOf: store.day)
        Page(title: title, subtitle: topics.count == 1 ? nil : "Short exercises for work, learning, reflection, and rest. Deeper ones open as your practice grows.", width: 820) {
            ForEach(topics) { topic in
                Panel(title: topics.count == 1 ? nil : topic.title, accent: GlimmerColor.sage, plain: true) {
                    VStack(spacing: 8) {
                        ForEach(topic.exercises.sorted { $0.stage < $1.stage }) { exercise in
                            exerciseRow(exercise, ahead: exercise.stage > level).accessibilityIdentifier("practice." + exercise.id)
                        }
                    }
                    .glassGroup(spacing: 8)
                }
            }
        }
    }

    private func exerciseRow(_ practice: Practice, ahead: Bool) -> some View {
        let exercise = practice.suggestion
        let active = store.journal.experiment?.suggestion.id == exercise.id
        let hasExperiment = store.journal.experiment != nil
        let queued = hasExperiment && store.journal.queued.contains { $0.id == exercise.id }
        let state: String
        if active { state = "In progress" }
        else if queued { state = "Queued" }
        else { state = hasExperiment ? "Queue experiment" : "Start experiment" }
        let note = ahead ? JourneyStage.aheadNote(practice.stage) + "\n" : practice.stage > 1 ? JourneyStage.name(practice.stage) + "\n" : ""
        return ActionRow(title: exercise.title, detail: "\(exercise.sub)\n\(note)\(state)", icon: ahead ? "leaf" : "flask",
                         tint: GlimmerColor.sage, trailing: active || queued ? "checkmark.circle" : "plus.circle") {
            store.startOrQueue(exercise)
        }
        .disabled(active || queued)
    }
}

struct ScreenTimeCheck: View {
    var body: some View {
        Page(title: "Check one app", subtitle: "Pick one app on this device and estimate how much time you spent in it over the past week. Then check your own device settings to see how close your guess was.", width: 680) {
            Panel(title: "Find your weekly total") {
                #if os(macOS)
                Text("Open Apple menu → System Settings → Screen Time → Daily Average → Week. On older macOS versions, open App & Website Activity instead and choose a week using the date menu.")
                Link("Apple’s Screen Time guide for Mac ↗", destination: URL(string: "https://support.apple.com/guide/mac-help/get-started-with-screen-time-mchlfafa9773/mac")!)
                #else
                Text("Open Settings → Screen Time → Daily Average → Week. On older iOS versions, tap See All App & Website Activity, then tap Week.")
                if UIDevice.current.userInterfaceIdiom == .pad {
                    Link("Apple’s Screen Time guide for iPad ↗", destination: URL(string: "https://support.apple.com/guide/ipad/set-up-screen-time-for-yourself-ipad88efc1ad/ipados")!)
                } else {
                    Link("Apple’s Screen Time guide for iPhone ↗", destination: URL(string: "https://support.apple.com/guide/iphone/set-up-screen-time-for-yourself-iphbfa595995/ios")!)
                }
                #endif
                Text("Glimmer never reads your Screen Time data. If reporting is off, select Turn On App & Website Activity in Screen Time and return once a week of activity is available.").font(.callout).foregroundStyle(.secondary)
            }
            Panel(title: "Try it for a week", accent: GlimmerColor.sage) {
                Text("Try one small change this week, like moving that app off your home screen or signing out after each visit. Check the total again next week and notice how your days felt.")
            }
        }
    }
}

struct ExperimentReview: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let experiment: Experiment

    var body: some View {
        let held = experiment.checkins.values.filter { $0 == .held }.count
        Page(title: "Review your experiment", subtitle: experiment.suggestion.title, width: 640) {
            Panel(title: "Seven check-ins", accent: GlimmerColor.ember, padding: 20) {
                HStack(spacing: 16) {
                    Stat(value: "\(held)", label: "Held", tint: GlimmerColor.sage)
                    Stat(value: "\(experiment.checkins.count - held)", label: "Slipped", tint: GlimmerColor.honey)
                }
                Divider()
                ForEach(experiment.checkins.keys.sorted(), id: \.self) { day in
                    LabeledContent(day, value: experiment.checkins[day]?.rawValue ?? "").font(.callout)
                }
            }
            Panel(title: "What now?", accent: GlimmerColor.ember, plain: true) {
                VStack(spacing: 8) {
                    ForEach(Experiment.Review.allCases) { choice in
                        ActionRow(title: choice.rawValue, detail: detail(choice), icon: icon(choice), tint: GlimmerColor.ember) {
                            if store.change({ $0.reviewExperiment(choice, on: store.day) }) { dismiss() }
                        }
                    }
                }
                .glassGroup(spacing: 8)
            }
        }
    }

    private func detail(_ review: Experiment.Review) -> String {
        switch review {
        case .keep: "Keep it as a practice in Challenges."
        case .adjust: "Try a smaller version for another week."
        case .drop: "Make room for something else."
        }
    }

    private func icon(_ review: Experiment.Review) -> String {
        switch review {
        case .keep: "checkmark.seal"
        case .adjust: "slider.horizontal.3"
        case .drop: "arrow.uturn.backward"
        }
    }
}

struct LocalCoachReflection: View {
    let summary: ReflectionSummary
    let tone: String?
    @State private var reflection: String?
    @State private var loading = false

    var body: some View {
        if #available(iOS 26, macOS 26, *), SystemLanguageModel.default.isAvailable, summary.moments.count >= 3 {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await generate() }
                } label: {
                    HStack(spacing: 8) {
                        if loading { ReflectionOrbit() } else { Image(systemName: "apple.intelligence") }
                        Text(loading ? "Reflecting…" : "Ask for an on-device reflection")
                    }
                }
                .glimmerButton(.standard, tint: GlimmerColor.dusk).buttonBorderShape(.capsule)
                .disabled(loading)
                if let reflection {
                    Text(reflection).font(.callout).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(GlimmerColor.dusk.opacity(0.10), in: .rect(cornerRadius: 14))
                }
                Label("Runs on this device. Only rating counts and averages are used.", systemImage: "lock")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @available(iOS 26, macOS 26, *)
    private func generate() async {
        loading = true
        defer { loading = false }
        let facts = summary.sources.prefix(5).enumerated().map { index, group in
            // Only computed statistics go to the model. Source names can contain arbitrary text.
            "Input \(index + 1): \(group.count) moments, average \(score(group.average)) on a -2 to +2 scale"
        }.joined(separator: "; ")
        let allowedTones = ["gentle", "direct", "curious", "data", "funny", "minimal", "mix"]
        let style = tone.flatMap { allowedTones.contains($0) ? $0 : nil } ?? "gentle"
        let session = LanguageModelSession(instructions: """
        You are a practical life coach. Offer one small, reversible reflection or question in two short
        sentences, in a \(style) tone. The person chose what to log. Use only the supplied statistics
        and never name the numbered inputs or guess what happened. Invite the person to consider a
        specific change at work, a small learning project, making something, or deliberate rest when
        relevant. Avoid medical advice and promises. Leisure can be worthwhile in its own right.
        """)
        do {
            reflection = try await session.respond(to: "Recent private journal statistics: \(facts)").content
        } catch {
            reflection = "An on-device reflection isn’t available right now. The patterns above are still based on your logs."
        }
    }
}

private func score(_ number: Double) -> String { number.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) }
