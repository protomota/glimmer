import SwiftUI

/// The three kinds of thing a moment can be about, each shown as a collapsible dropdown.
private enum SourceGroup: String {
    case apps = "Apps & sites", activities = "Activities", people = "People"

    /// The glyph kind for this group's rows.
    var kind: String {
        switch self {
        case .apps: "app"
        case .activities: "activity"
        case .people: "person"
        }
    }

    var icon: String {
        switch self {
        case .apps: "square.grid.2x2"
        case .activities: "figure.walk"
        case .people: "person.2"
        }
    }
}

/// The inline control mirrors the date pill and calendar popover in OpenTalon.
private struct MomentDateControl: View {
    @Binding var date: Date
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.readingTheme) private var theme
    @State private var pending = Date()
    @State private var showingCalendar = false

    private var selectedDay: Binding<Date> {
        Binding(get: { calendar.startOfDay(for: pending) }, set: { day in
            let time = calendar.dateComponents([.hour, .minute], from: pending)
            let combined = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0,
                                         of: day, matchingPolicy: .nextTimePreservingSmallerComponents)
            pending = min(combined ?? day, .now)
        })
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("When").font(.callout)
            Spacer(minLength: 6)
            Button {
                pending = date
                showingCalendar = true
            } label: {
                Label(date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()), systemImage: "calendar")
                    .font(.callout.weight(.medium))
                    .frame(minHeight: 24)
            }
            .glimmerButton()
            .accessibilityLabel("Moment date and time")
            .accessibilityValue(date.formatted(date: .long, time: .shortened))
            .accessibilityHint("Opens a calendar and time controls")
            .accessibilityIdentifier("momentDate")
            .popover(isPresented: $showingCalendar, arrowEdge: .bottom) {
                #if os(macOS)
                calendarContent
                    .frame(width: 304)
                    .padding(14)
                    .background(theme.surface)
                #else
                ScrollView {
                    calendarContent.frame(maxWidth: 350)
                        .frame(maxWidth: .infinity)
                        .padding(18)
                }
                .presentationCompactAdaptation(.sheet)
                .background(theme.surface)
                #endif
            }
        }
    }

    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlimmerCalendarGrid(selection: selectedDay, latestDay: calendar.startOfDay(for: .now))
            HStack {
                Text("Time").font(.callout)
                Spacer()
                timeMenu(.hour)
                timeMenu(.minute)
            }
            HStack {
                Spacer(minLength: 0)
                Button("Cancel") { showingCalendar = false }.glimmerButton()
                Button("Apply") {
                    date = min(pending, .now)
                    showingCalendar = false
                }
                .glimmerButton(.prominent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("applyMomentDate")
            }
        }
        .tint(theme.selectionInk)
    }

    private func timeMenu(_ component: Calendar.Component) -> some View {
        let isHour = component == .hour
        let hour = calendar.component(.hour, from: pending)
        let minute = calendar.component(.minute, from: pending)
        let selected = isHour ? hour : minute
        let title = isHour ? "Hour" : "Minute"
        return Menu {
            ForEach(0..<(isHour ? 24 : 60), id: \.self) { value in
                let option = calendar.date(bySettingHour: isHour ? value : hour, minute: isHour ? minute : value,
                                           second: 0, of: pending, matchingPolicy: .strict)
                    .flatMap { calendar.isDate($0, inSameDayAs: pending) && $0 <= .now ? $0 : nil }
                Button(label(value, isHour: isHour)) {
                    if let option { pending = option }
                }
                .disabled(option == nil)
            }
        } label: {
            HStack(spacing: 6) {
                Text(label(selected, isHour: isHour)).monospacedDigit()
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(theme.selectionInk)
            .padding(.horizontal, 9)
            .frame(minHeight: 38)
            .background(theme.selectionFill, in: .capsule)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(title)
        .accessibilityValue(label(selected, isHour: isHour))
    }

    private func label(_ value: Int, isHour: Bool) -> String {
        guard isHour, let time = calendar.date(bySettingHour: value, minute: 0, second: 0,
                                              of: pending, matchingPolicy: .strict),
              calendar.isDate(time, inSameDayAs: pending) else {
            return value.formatted(.number.precision(.integerLength(2)).locale(locale))
        }
        return time.formatted(.dateTime.hour().locale(locale))
    }
}

struct MomentFlow: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readingTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var sourceGlyph = 20.0
    @ScaledMetric(relativeTo: .body) private var sourceCheck = 18.0
    let catalog: Catalog
    @State private var step = 0
    @State private var source = "TikTok"
    @State private var custom = ""
    @State private var date = Date()
    @State private var tags: [String] = []
    @State private var value = 0.5
    @State private var decision = Decision.same
    @State private var openGroup: SourceGroup?

    private var sources: [String] { catalog.sources + store.journal.customSources }
    private var possibleTags: [String] {
        if catalog.activities.contains(source) { return ["Solo", "With others", "At home", "Outside", "Intentional", "Unplanned"] }
        if catalog.people.contains(source) { return ["In person", "Online", "Supportive", "Social", "Work", "Family"] }
        return catalog.tags[source] ?? catalog.defaultTags
    }

    var body: some View {
        NavigationStack {
            Page(title: ["What did you do?", "What kind of content?", "How did it leave you?"][step],
                 kicker: "Log a moment", subtitle: subtitle, width: 600) {
                StepDots(current: step, total: 3)
                switch step {
                case 0: sourceStep
                case 1: tagStep
                default: dialStep
                }
                if let notice = store.notice, notice.hasPrefix("Glimmer couldn’t save") {
                    Label(notice, systemImage: "exclamationmark.triangle").foregroundStyle(GlimmerColor.ember)
                }
            }
            .id(step)
            #if DEBUG
            .onAppear {
                if let value = ProcessInfo.processInfo.environment["GLIMMER_LOG_STEP"].flatMap(Int.init), step == 0 {
                    step = min(2, max(0, value))
                }
                if let name = ProcessInfo.processInfo.environment["GLIMMER_LOG_OPEN"] {
                    openGroup = SourceGroup(rawValue: name)
                }
            }
            #endif
            .actionBar(width: 600) {
                SheetCancel { dismiss() }
                if step > 0 {
                    GlassIconButton(label: "Back", systemImage: "chevron.left") { step -= 1 }
                }
                switch step {
                case 0: PrimaryAction(title: "Continue") { step += 1 }.disabled(source.isEmpty)
                case 1: PrimaryAction(title: tags.isEmpty ? "Skip tags" : "Continue") { step += 1 }
                default: PrimaryAction(title: "Save log", systemImage: "checkmark", action: save).accessibilityIdentifier("saveMoment")
                }
            }
            .sheetCancel { dismiss() }
        }
        #if os(macOS)
        .frame(minWidth: 580, idealWidth: 620, minHeight: 640, idealHeight: 700)
        #endif
    }

    private var subtitle: String {
        switch step {
        case 0: "An app, an activity or time with someone."
        case 1: "Choose up to three tags, or continue without them."
        default: "Turn the dial to how you feel now, not how much you wanted it."
        }
    }

    private var sourceStep: some View {
        VStack(spacing: 10) {
            sourceSection(.apps, items: sources)
            sourceSection(.activities, items: catalog.activities)
            sourceSection(.people, items: catalog.people)
            Panel(padding: 16) {
                MomentDateControl(date: $date)
            }
            .padding(.top, 10)
        }
        .accessibilityIdentifier("momentSource")
    }

    /// One collapsible dropdown: a glass header showing the current choice, and its options when open.
    private func sourceSection(_ group: SourceGroup, items: [String]) -> some View {
        let chosen = items.contains(source) ? source : nil
        let isOpen = openGroup == group
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                openGroup = isOpen ? nil : group
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: group.icon)
                        .font(.system(size: sourceGlyph, weight: .medium))
                        .foregroundStyle(chosen == nil ? Color.secondary : theme.selectionInk)
                        .frame(minWidth: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.rawValue).font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                        Text(chosen ?? "\(items.count) to choose from").font(.subheadline)
                            .foregroundStyle(chosen == nil ? Color.secondary : Color.primary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    if chosen != nil {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: sourceCheck))
                            .foregroundStyle(theme.selectionInk)
                            .accessibilityHidden(true)
                    }
                    Image(systemName: "chevron.down").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        .frame(minWidth: 20)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: isOpen)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 13)
                .frame(maxWidth: .infinity, minHeight: RowLabel.minHeight + 26, alignment: .leading)
                .contentShape(.rect)
            }
            .glassRow(tint: theme.selectionInk, selected: chosen != nil)
            .accessibilityLabel(group.rawValue)
            .accessibilityValue(chosen ?? "Nothing chosen")
            .accessibilityHint(isOpen ? "Collapses the list" : "Shows the list")
            ReadingDisclosure(expanded: isOpen) { visible in
                ChoiceList(items: items, selection: chosen, visible: visible,
                           favorites: store.journal.favoriteSources ?? [], recents: recentSources,
                           prompt: group == .apps ? "Search or add an app or site" : "Search \(group.rawValue.lowercased())",
                           alphabetical: group == .apps,
                           kind: group.kind,
                           onSelect: choose, onToggleFavorite: toggleFavorite,
                           onAdd: group == .apps ? { custom = $0; addSource() } : nil)
                    .padding(.bottom, 8)
            }
        }
    }

    /// Sources from past logs, most recent first.
    private var recentSources: [String] {
        var seen = Set<String>()
        return store.journal.moments.sorted { $0.date > $1.date }.map(\.source).filter { seen.insert($0).inserted }
    }

    private func choose(_ name: String) {
        if source != name { tags = [] }
        source = name
        openGroup = nil
    }

    private func toggleFavorite(_ name: String) {
        store.change { journal in
            var favorites = journal.favoriteSources ?? []
            if let index = favorites.firstIndex(of: name) { favorites.remove(at: index) } else { favorites.append(name) }
            journal.favoriteSources = favorites
        }
    }

    private var tagStep: some View {
        Panel(title: source) {
            FlowLayout {
                ForEach(possibleTags, id: \.self) { tag in
                    Chip(label: tag, selected: tags.contains(tag), tint: theme.selectionInk) {
                        if let index = tags.firstIndex(of: tag) { tags.remove(at: index) }
                        else if tags.count < 3 { tags.append(tag) }
                    }
                }
            }
            .glassGroup(spacing: 8)
            Text("\(tags.count) of 3 chosen").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var dialStep: some View {
        Panel(padding: 22) {
            HStack {
                Eyebrow(source)
                Spacer()
                if !tags.isEmpty { Text(tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
            }
            ReflectionDial(title: "Aftertaste", words: Moment.words,
                           colors: ["596078", "7c8699", "9db2c4", "64a6e8", "3d8ef0"].map(Color.init(hex:)), value: $value)
            Divider()
            Text("Want more or less of this?").font(.headline)
            GlassSegments(label: "Want more or less of this?", options: [
                GlassSegment(value: Decision.less, title: Decision.less.title, symbol: "arrow.down"),
                GlassSegment(value: Decision.same, title: Decision.same.title, symbol: "equal"),
                GlassSegment(value: Decision.more, title: Decision.more.title, symbol: "arrow.up"),
            ], selection: $decision)
        }
    }

    private func addSource() {
        let name = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let existing = (sources + catalog.activities + catalog.people).first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            source = existing
        } else {
            guard store.change({ $0.customSources.append(name) }) else { return }
            source = name
        }
        tags = []
        custom = ""
        openGroup = nil
    }

    private func save() {
        let moment = Moment(source: source, kind: Moment.kind(of: source, catalog: catalog), tags: tags, value: value, decision: decision,
                            date: date, day: CalendarDay.key(date))
        let previousAward = store.earnedCoins?.id
        if store.change({ $0.record(moment) }) {
            if store.earnedCoins?.id == previousAward { store.notice = "Logged. Thanks for noticing." }
            dismiss()
        }
    }
}

struct EnergyFlow: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let catalog: Catalog
    @State private var value = 0.5

    var body: some View {
        NavigationStack {
            Page(title: "How’s your energy right now?", kicker: store.day.formatted(date: .complete, time: .omitted),
                 subtitle: "Ten seconds. It shapes how big today feels.", width: 560) {
                // The dial sits straight on the page, and the line under it answers as it turns.
                VStack(spacing: 6) {
                    ReflectionDial(title: "Energy", words: catalog.energy.map(\.label),
                                   colors: catalog.energy.map { Color(hex: $0.color) }, value: $value)
                    let level = catalog.energy[Moment.step(value)]
                    Text(catalog.energyMessages[level.id] ?? "")
                        .font(GlimmerFont.reading(.title3)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 360, minHeight: 56, alignment: .top)
                        .id(level.id)
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
                        .accessibilityIdentifier("energy.message")
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: Moment.step(value))
            }
            .actionBar(width: 560) {
                SheetCancel { dismiss() }
                PrimaryAction(title: "Set today’s energy", systemImage: "bolt.heart") {
                    let level = catalog.energy[Moment.step(value)]
                    if store.change({ $0.recordEnergy(.init(level: level.id, value: value), on: store.day) }) {
                        store.notice = catalog.energyMessages[level.id]
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .sheetCancel { dismiss() }
        }
        .onAppear { value = store.journal.energy[store.todayKey]?.value ?? 0.5 }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 600, idealHeight: 640)
        #endif
    }
}
