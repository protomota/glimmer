import SwiftUI

struct ChallengesView: View {
    @Environment(\.readingTheme) private var theme
    @Environment(JournalStore.self) private var store
    let catalog: Catalog

    var body: some View {
        let level = store.journal.journeyLevel(asOf: store.day)
        let stages = Array(Set(catalog.challenges.map(\.stage))).sorted()
        Page(title: "Challenges", subtitle: "Guided challenges you can actually finish. They deepen as your practice grows, and every one is yours to try anytime.", width: 940) {
            ForEach(stages, id: \.self) { stage in
                Panel(title: JourneyStage.name(stage), plain: true) {
                    Label(stage > level ? "\(JourneyStage.asks(stage)). Glimmer suggests these after \(JourneyStage.rank(for: stage).rawValue)." : JourneyStage.asks(stage) + ".",
                          systemImage: stage > level ? "leaf" : "sparkles")
                        .font(.callout).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                        ForEach(catalog.challenges.filter { $0.stage == stage }) { challenge in
                            let index = catalog.challenges.firstIndex { $0.id == challenge.id } ?? 0
                            card(challenge, slot: 51 + index)
                        }
                    }
                }
            }
            let kept = store.journal.history.filter { $0.review == .keep }
            if !kept.isEmpty {
                Panel(title: "Experiments you kept", accent: GlimmerColor.sage, plain: true) {
                    ForEach(kept) { Label($0.suggestion.title, systemImage: "checkmark.seal").foregroundStyle(.primary) }
                }
            }
        }
    }

    private func card(_ challenge: Challenge, slot: Int) -> some View {
        let unlocked = challenge.id != "coffee" || store.journal.coffeeUnlocked
        let done = store.journal.challenges[challenge.id] != nil
        return Panel(padding: 14) {
            ZStack(alignment: .topLeading) {
                Artwork(slot: slot, height: 150, corner: 14)
                    .saturation(unlocked ? 1 : 0).opacity(unlocked ? 1 : 0.5)
                Text(done ? "Completed" : unlocked ? "\(challenge.mins) min · +\(challenge.coins)" : "Locked")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(theme.surface.opacity(0.92), in: .capsule)
                    .padding(10)
            }
            Text(challenge.title).font(GlimmerFont.display(.title3, weight: .bold))
            Text(challenge.sub).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if unlocked {
                LinkRow(title: done ? "Do it again" : "Start", icon: done ? "arrow.counterclockwise" : "play.fill",
                        tint: GlimmerColor.honey) { ChallengeView(challenge: challenge) }
                    .accessibilityLabel(challenge.title)
            } else {
                Label("Unlocks at 80 coins · \(max(0, 80 - store.journal.coins)) to go", systemImage: "lock")
                    .font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct ChallengeView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let challenge: Challenge
    @State private var step = 0
    @State private var choice = ""
    @State private var deadline: Date?

    private var gallerySlot: Int { 51 + (store.catalog?.challenges.firstIndex { $0.id == challenge.id } ?? 0) }
    private var actionStep: Int { challenge.teach.count + 2 }
    private var total: Int { actionStep + 2 }

    var body: some View {
        Page(title: heading, kicker: "Tiny win · \(challenge.title)", width: 640) {
            StepDots(current: min(step, total - 1), total: total)
            switch step {
            case 0:
                Artwork(slot: gallerySlot, height: 230)
                Panel {
                    Text(challenge.sub).font(GlimmerFont.display(.title3))
                    Label("\(challenge.mins) minutes · +\(challenge.coins) coins", systemImage: "timer")
                        .foregroundStyle(.secondary)
                }
            case 1...challenge.teach.count:
                challengePage(challenge.teach[step - 1])
            case actionStep - 1:
                VStack(spacing: 8) {
                    ForEach(challenge.opts) { option in
                        ActionRow(title: option.l, emoji: option.e, tint: GlimmerColor.honey,
                                  selected: choice == option.l, tick: choice == option.l) { choice = option.l }
                    }
                }
                .glassGroup(spacing: 8)
            case actionStep:
                challengePage(challenge.action)
                timer
            default:
                Panel(padding: 22) {
                    HStack(spacing: 14) {
                        Text("+\(challenge.coins) coins").font(GlimmerFont.display(.title2, weight: .bold))
                            .foregroundStyle(GlimmerColor.honey)
                    }
                }
                challengePage(challenge.done)
                Panel(title: "How did it feel?", accent: GlimmerColor.honey) {
                    FlowLayout {
                        ForEach(["Lighter", "About the same", "Harder than expected"], id: \.self) { answer in
                            Chip(label: answer, selected: store.journal.challenges[challenge.id]?.feedback == answer,
                                 tint: GlimmerColor.honey) {
                                store.change { $0.challenges[challenge.id]?.feedback = answer }
                            }
                        }
                    }
                    .glassGroup(spacing: 8)
                }
            }
        }
        .actionBar(width: 640) {
            if step > 0 && step <= actionStep {
                GlassIconButton(label: "Back", systemImage: "chevron.left") { deadline = nil; step -= 1 }
            }
            switch step {
            case 0: next("Get started")
            case 1...challenge.teach.count: next("Continue")
            case actionStep - 1: next("Continue").disabled(choice.isEmpty)
            case actionStep: PrimaryAction(title: "I’m done", systemImage: "checkmark", action: finish)
            default: PrimaryAction(title: "Back to challenges") { dismiss() }
            }
        }
        .navigationTitle("Tiny win")
        .hidesTabBar()
    }

    @ViewBuilder private var timer: some View {
        Panel(title: "Timer", accent: GlimmerColor.honey) {
            if let deadline {
                TimelineView(.periodic(from: .now, by: 1)) { tick in
                    let seconds = max(0, Int(ceil(deadline.timeIntervalSince(tick.date))))
                    let total = Double(challenge.mins * 60)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                            .font(.system(size: 54, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                            .accessibilityLabel("\(seconds) seconds left")
                        Meter(value: 1 - Double(seconds) / max(1, total), tint: GlimmerColor.honey)
                    }
                    .onChange(of: seconds) { _, value in if value == 0 { finish() } }
                }
                SecondaryAction(title: "Stop timer", systemImage: "stop.fill") { self.deadline = nil }
            } else {
                Text("Optional. Run a short timer so the time stays visible.").foregroundStyle(.secondary)
                SecondaryAction(title: "Start \(challenge.mins)-minute timer", systemImage: "timer") {
                    deadline = .now.addingTimeInterval(Double(challenge.mins) * 60)
                }
            }
        }
    }

    private var heading: String {
        if step == 0 { return challenge.title }
        if step <= challenge.teach.count { return challenge.teach[step - 1].title }
        if step == actionStep - 1 { return challenge.q }
        return step == actionStep ? challenge.action.title : challenge.done.title
    }

    private func challengePage(_ page: Challenge.Page) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if page.hero != nil { Artwork(slot: gallerySlot + step, height: 210) }
            Panel {
                ForEach(Array(page.lines.enumerated()), id: \.offset) { _, line in
                    Text(line).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func next(_ title: String) -> PrimaryAction { PrimaryAction(title: title) { step += 1 } }

    private func finish() {
        guard step == actionStep else { return }
        if store.change({ $0.completeChallenge(challenge, choice: choice, on: store.day) }) {
            deadline = nil
            step += 1
        }
    }
}

struct HabitsView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    let catalog: Catalog
    @State private var monthly = false
    @State private var offset = 0
    private let calendar = Calendar.current

    private var month: Date { calendar.date(byAdding: .month, value: offset, to: store.day) ?? store.day }
    private var start: Date { calendar.dateInterval(of: .month, for: month)?.start ?? month }
    private var dates: [Date] {
        (calendar.range(of: .day, in: .month, for: start) ?? 1..<2).compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: start)
        }
    }
    private var leading: Int { (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7 }
    private var doneToday: Int { catalog.habits.filter { contains($0, store.day) }.count }
    private var compact: Bool {
        #if os(macOS)
        false
        #else
        sizeClass == .compact
        #endif
    }

    var body: some View {
        Page(title: "Habits", subtitle: "Notice what you’re making room for.", width: 860) {
            GlassSegments(label: "View", options: [GlassSegment(value: false, title: "Today"), GlassSegment(value: true, title: "Month")],
                          selection: $monthly)
                .frame(maxWidth: 320)

            if monthly { monthView } else { todayView }
        }
    }

    private var todayView: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) {
                habitStones.frame(minWidth: 380)
                moodSky.frame(width: 300)
            }
            // On a phone the habits come first and fit on one screen, with the sky just below.
            VStack(alignment: .leading, spacing: 22) { habitStones; moodSky }
        }
    }

    private var habitStones: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Today’s habits")
                Spacer()
                Text("\(doneToday) of \(catalog.habits.count)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(doneToday)))
                    .animation(.easeOut(duration: reduceMotion ? 0.18 : 0.32), value: doneToday)
                    .accessibilityLabel("\(doneToday) of \(catalog.habits.count) habits done today")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 80 : 100), spacing: compact ? 8 : 10, alignment: .top)],
                      alignment: .leading, spacing: 20) {
                ForEach(catalog.habits) { habit in
                    HabitStone(icon: habit.icon, name: habit.name, week: week(habit), size: compact ? 70 : 78) {
                        toggle(habit, store.day)
                    }
                        .accessibilityIdentifier("habit." + habit.id)
                }
            }
            Text("Each ring is your last seven days.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var moodSky: some View {
        MoodSky(mood: store.journal.moods[store.todayKey]) { value in
            store.change { $0.moods[store.todayKey] = value }
        }
    }

    private var monthView: some View {
        VStack(spacing: 16) {
            HStack {
                GlassIconButton(label: "Previous month", systemImage: "chevron.left") { offset -= 1 }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(GlimmerFont.display(.title3, weight: .bold))
                Spacer()
                GlassIconButton(label: "Next month", systemImage: "chevron.right") { offset += 1 }.disabled(offset >= 0)
            }
            .glassGroup()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 16)], spacing: 16) {
                ForEach(catalog.habits) { habit in
                    Panel {
                        let logged = dates.filter { contains(habit, $0) }.count
                        HStack {
                            Label {
                                Text(habit.name).font(.headline)
                            } icon: {
                                GlyphTile(Glyph.symbol(icon: habit.icon, name: habit.name, category: "habit"), tint: Glyph.tint(for: "habit"))
                            }
                            Spacer()
                            Text("\(logged) days").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(logged)))
                                .animation(.easeOut(duration: reduceMotion ? 0.18 : 0.32), value: logged)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                            ForEach(0..<7, id: \.self) { index in
                                Text(calendar.veryShortWeekdaySymbols[(index + calendar.firstWeekday - 1) % 7])
                                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 38) }
                            ForEach(dates, id: \.self) { day($0, habit) }
                        }
                    }
                }
            }
        }
    }

    /// A day in the month: a plain number until it is done, then a sage stone.
    private func day(_ date: Date, _ habit: Habit) -> some View {
        let on = contains(habit, date)
        let today = calendar.isDate(date, inSameDayAs: store.day)
        let future = CalendarDay.distance(date, store.day) < 0
        return Button { toggle(habit, date) } label: {
            Text(date.formatted(.dateTime.day())).font(.footnote.monospacedDigit().weight(on || today ? .semibold : .regular))
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .foregroundStyle(on ? Color(light: "ffffff", dark: "1c1c1b") : .primary)
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(GlimmerColor.sage).scaleEffect(on ? 1 : 0.4).opacity(on ? 1 : 0)
                        .animation(on && !reduceMotion ? .spring(duration: 0.38, bounce: 0.45) : .easeOut(duration: 0.14), value: on)
                    if today && !on { Circle().strokeBorder(Color.primary.opacity(0.42), lineWidth: 1.5) }
                }
                .frame(maxWidth: .infinity, minHeight: 38)
                .contentShape(.rect)
        }
        .buttonStyle(PressStyle(scale: 0.85))
        .tickFeedback(on)
        .disabled(future)
        .opacity(future ? 0.3 : 1)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func contains(_ habit: Habit, _ date: Date) -> Bool {
        store.journal.habits[habit.id]?.contains(CalendarDay.key(date)) == true
    }

    /// The last seven days for a habit, oldest first, ending today.
    private func week(_ habit: Habit) -> [Bool] {
        (0..<7).map { back in
            calendar.date(byAdding: .day, value: back - 6, to: store.day).map { contains(habit, $0) } ?? false
        }
    }

    private func toggle(_ habit: Habit, _ date: Date) {
        store.change { $0.toggleHabit(habit.id, on: date) }
    }
}

struct CleaningView: View {
    @Environment(JournalStore.self) private var store
    let catalog: Catalog

    @State private var duration: Int?
    private let icons = ["room-kitchen": "frying.pan.fill", "room-bath": "bathtub.fill", "room-bed": "bed.double.fill",
                         "room-living": "sofa.fill", "room-office": "lamp.desk.fill", "room-garage": "door.garage.closed"]

    private var lists: [CleaningList] { catalog.cleaning.rooms + [catalog.cleaning.daily] + catalog.cleaning.speed }

    private var favorites: [HomeChore] {
        let saved = store.journal.favoriteChores ?? []
        return chores.filter { saved.contains($0.id) }
    }

    private var chores: [HomeChore] {
        lists.flatMap { list in list.items.indices.map { HomeChore.cleaning(list, $0) } }
            + store.maintenanceChores.map(HomeChore.maintenance)
    }

    private var recent: [CompletedChore] {
        let first = Calendar.current.date(byAdding: .day, value: -29, to: store.day) ?? store.day
        let days = CalendarDay.key(first)...store.todayKey
        let choreRecords = chores.flatMap { chore in
            (store.journal.recentChores?[chore.id] ?? []).filter { days.contains($0) }.map {
                CompletedChore(id: chore.id + ":" + $0, title: chore.title, source: source(of: chore), day: $0)
            }
        }
        let finishedLists = lists.compactMap { list -> CompletedChore? in
            guard let day = store.journal.cleaningLast[list.id], days.contains(day) else { return nil }
            return CompletedChore(id: "finished:" + list.id, title: "Finished the \(list.name) checklist", source: nil, day: day)
        }
        return (choreRecords + finishedLists).sorted {
            if $0.day != $1.day { return $0.day > $1.day }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.id < $1.id
        }
    }

    var body: some View {
        Page(title: "Cleaning & maintenance", width: 800) {
            let rooms = catalog.cleaning.rooms
            if let room = rooms.first(where: { !(store.journal.cleaningChecks[$0.id] ?? []).isEmpty }) ??
                rooms.min(by: { (store.journal.cleaningLast[$0.id] ?? "") < (store.journal.cleaningLast[$1.id] ?? "") }) {
                Panel(padding: 20) {
                    HStack(spacing: 18) {
                        Artwork(slot: 72, height: 105, corner: 12).frame(width: 112)
                        VStack(alignment: .leading, spacing: 7) {
                            Eyebrow("Suggested next")
                            Text(room.name).font(GlimmerFont.reading(.title))
                            if let step = room.items.first { Text(step).foregroundStyle(.secondary) }
                            NavigationLink("Open checklist") { CleaningSession(list: room) }.glimmerButton()
                        }
                    }
                }
            }
            Panel(title: "Favorites", plain: true) {
                let saved = favorites
                if saved.isEmpty {
                    Text("Tap the star on any chore to keep it here.").foregroundStyle(.secondary)
                } else {
                    ForEach(saved.prefix(5)) { chore in choreRow(chore) }
                    if saved.count > 5 {
                        NavigationLink("All favorites") { FavoriteChores(chores: saved, source: source) }
                            .glimmerButton()
                    }
                }
            }
            Panel(title: "How much time do you have?", plain: true) {
                FlowLayout(spacing: 6) {
                    ForEach(catalog.cleaning.speed) { item in
                        if let minutes = item.mins {
                            Button("\(minutes) min") { duration = minutes }
                                .glimmerButton(minutes == (duration ?? catalog.cleaning.speed.first?.mins) ? .selected : .standard, tint: GlimmerColor.sage)
                                .accessibilityAddTraits(minutes == (duration ?? catalog.cleaning.speed.first?.mins) ? .isSelected : [])
                        }
                    }
                }
                if let item = catalog.cleaning.speed.first(where: { $0.mins == duration }) ?? catalog.cleaning.speed.first {
                    NavigationLink(item.name) { CleaningSession(list: item) }.buttonStyle(.borderless)
                }
                link(catalog.cleaning.daily, icon: "repeat")
            }
            Panel(title: "By room", plain: true) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], alignment: .leading, spacing: 14) {
                    ForEach(rooms) { room in
                        NavigationLink { CleaningSession(list: room) } label: {
                            HStack(spacing: 12) {
                                GlyphTile(icons[room.id] ?? "bubbles.and.sparkles.fill", tint: GlimmerColor.accent, size: 34)
                                Text(room.name).font(.headline)
                            }.frame(minHeight: 44)
                        }.buttonStyle(.plain)
                    }
                }
                NavigationLink {
                    Page(title: "House systems") {
                        MaintenanceChores(chores: store.maintenanceChores.filter { $0.room == "room-house" })
                    }
                } label: {
                    Label("House systems", systemImage: "wrench.and.screwdriver")
                }
                .glimmerButton()
            }
            Panel(title: "Recently completed", plain: true) {
                let records = recent
                if records.isEmpty {
                    Text("Chores you check off will appear here with the day you did them.").foregroundStyle(.secondary)
                } else {
                    completedRows(records.prefix(5))
                    if records.count > 5 {
                        NavigationLink("See all") {
                            Page(title: "Recently completed", subtitle: "The last 30 days") {
                                completedRows(recent[...])
                            }
                        }
                        .glimmerButton()
                    }
                }
            }
        }
    }

    private func source(of chore: HomeChore) -> String {
        switch chore {
        case .cleaning(let list, _): list.name
        case .maintenance(let item):
            catalog.cleaning.rooms.first(where: { $0.id == item.room })?.name ?? "House systems"
        }
    }

    private func choreRow(_ chore: HomeChore) -> some View {
        HomeChoreRow(chore: chore, detail: source(of: chore))
    }

    private func completedRows(_ records: ArraySlice<CompletedChore>) -> some View {
        ForEach(records) { record in
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title).font(.callout.weight(.semibold))
                Text([record.source, choreDate(record.day)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                Divider().accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func link(_ list: CleaningList, icon: String) -> some View {
        let checks = store.journal.cleaningChecks[list.id]?.count ?? 0
        let detail: String? = if let date = store.journal.cleaningLast[list.id] { "Last finished \(choreDate(date))" }
            else if checks > 0 { "\(checks) of \(list.items.count) done" }
            else { list.sub }
        return LinkRow(title: list.name, detail: detail, icon: icon, tint: GlimmerColor.accent) {
            CleaningSession(list: list)
        }
    }
}

private struct CompletedChore: Identifiable {
    let id: String
    let title: String
    let source: String?
    let day: String
}

private enum HomeChore: Identifiable {
    case cleaning(CleaningList, Int)
    case maintenance(MaintenanceChore)

    var id: String {
        switch self {
        case .cleaning(let list, let index): list.choreID(at: index)
        case .maintenance(let chore): "maintenance:" + chore.id
        }
    }

    var title: String {
        switch self {
        case .cleaning(let list, let index): list.items[index]
        case .maintenance(let chore): chore.title
        }
    }
}

private func choreDate(_ day: String) -> String {
    guard let date = PracticeDate.parse(day) else { return day }
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    return date.formatted(.dateTime.month(.abbreviated).day())
}

private struct FavoriteChores: View {
    @Environment(JournalStore.self) private var store
    let chores: [HomeChore]
    let source: (HomeChore) -> String
    @State private var visible: [HomeChore] = []

    var body: some View {
        Page(title: "Favorites") {
            ForEach(visible) { chore in HomeChoreRow(chore: chore, detail: source(chore)) }
            if visible.isEmpty {
                Text("Tap the star on any chore to keep it here.").foregroundStyle(.secondary)
            }
        }
        .onAppear { visible = chores.filter { store.journal.favoriteChores?.contains($0.id) == true } }
    }
}

private struct HomeChoreRow: View {
    @Environment(JournalStore.self) private var store
    let chore: HomeChore
    var detail: String? = nil
    var compactMaintenance: MaintenanceChore? = nil

    private var checked: Bool {
        switch chore {
        case .cleaning(let list, let index): store.journal.cleaningChecks[list.id]?.contains(index) == true
        case .maintenance: store.journal.recentChores?[chore.id]?.contains(store.todayKey) == true
        }
    }

    var body: some View {
        let favorite = store.journal.favoriteChores?.contains(chore.id) == true
        HStack(alignment: .center, spacing: 0) {
            Button {
                store.change { journal in
                    switch chore {
                    case .cleaning(let list, let index): journal.toggleCleaningChore(list, at: index, on: store.day)
                    case .maintenance: journal.toggleMaintenanceChore(chore.id, on: store.day)
                    }
                }
            } label: {
                if compactMaintenance != nil {
                    Tick(done: checked, size: 24)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                        .accessibilityLabel((checked ? "Undo " : "Complete ") + chore.title)
                } else {
                    HStack(spacing: 2) {
                        Tick(done: checked, size: 24).frame(width: 44, height: 44)
                        GlyphTile(Glyph.symbol(name: chore.title, category: "cleaning"), tint: Glyph.tint(for: "cleaning"))
                            .padding(.trailing, 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chore.title).font(.body)
                                .foregroundStyle(checked ? Color.secondary : Color.primary)
                            if let detail {
                                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                    }
                    .padding(.vertical, detail == nil ? 0 : 4)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
            }
            .buttonStyle(RowPressStyle())
            .tickFeedback(checked)
            .accessibilityAddTraits(checked ? .isSelected : [])
            .accessibilityIdentifier(chore.id)

            if let item = compactMaintenance {
                NavigationLink {
                    Page(title: item.title, width: 660) {
                        Text(item.tip)
                            .font(GlimmerFont.reading(.title3))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } label: {
                    HStack(spacing: 5) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title).font(.callout.weight(.semibold))
                            Text(detail ?? item.cadence).font(.caption).foregroundStyle(GlimmerColor.dusk)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Open maintenance tip")
            }

            Button {
                store.change { $0.toggleFavoriteChore(chore.id) }
            } label: {
                Image(systemName: favorite ? "star.fill" : "star")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(favorite ? GlimmerColor.honey : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel((favorite ? "Remove from favorites" : "Add to favorites") + ", " + chore.title)
            .accessibilityIdentifier("favorite:" + chore.id)
            .help(favorite ? "Remove from favorites" : "Add to favorites")
        }
    }
}

struct MaintenanceChores: View {
    @Environment(JournalStore.self) private var store
    let chores: [MaintenanceChore]
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 10) {
            ForEach(chores) { item in
                let chore = HomeChore.maintenance(item)
                let last = store.journal.recentChores?[chore.id]?.max()
                let status = last.map { $0 == store.todayKey ? "Done today" : "Last done \(choreDate($0))" }
                let summary = [item.cadence, status].compactMap { $0 }.joined(separator: " · ")
                HomeChoreRow(chore: chore, detail: compact ? summary : summary + "\n" + item.tip,
                             compactMaintenance: compact ? item : nil)
                if compact, item.id != chores.last?.id { Divider().accessibilityHidden(true) }
            }
        }
    }
}

struct CleaningSession: View {
    @Environment(JournalStore.self) private var store
    let list: CleaningList
    @State private var section: Section = .cleaning

    private enum Section: String, CaseIterable { case cleaning = "Cleaning", maintenance = "Maintenance" }

    var body: some View {
        let maintenance = store.maintenanceChores.filter { $0.room == list.id }
        Page(title: list.name, width: maintenance.isEmpty ? 640 : 880) {
            if maintenance.isEmpty {
                checklist
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        Panel(title: "Cleaning", plain: true) { checklist }.frame(minWidth: 320)
                        Panel(title: "Maintenance", plain: true) { MaintenanceChores(chores: maintenance) }.frame(minWidth: 300)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        GlassSegments(label: "Chore type", options: Section.allCases.map { GlassSegment(value: $0, title: $0.rawValue) },
                                      selection: $section)
                        if section == .cleaning { checklist }
                        else { MaintenanceChores(chores: maintenance) }
                    }
                }
            }
        }
    }

    private var checklist: some View {
        let checks = store.journal.cleaningChecks[list.id] ?? []
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(checks.count) of \(list.items.count) done").foregroundStyle(.secondary)
            Meter(value: Double(checks.count) / Double(max(1, list.items.count)), tint: GlimmerColor.softBlue)
            VStack(spacing: 0) {
                ForEach(list.items.indices, id: \.self) { index in
                    HomeChoreRow(chore: .cleaning(list, index))
                    if index < list.items.count - 1 { Divider().opacity(0.6).padding(.leading, 44) }
                }
            }
            .padding(.leading, -8)
            if !checks.isEmpty {
                SecondaryAction(title: "Start a fresh checklist", systemImage: "arrow.counterclockwise") {
                    store.change { $0.cleaningChecks[list.id] = [] }
                }
            }
        }
    }
}
