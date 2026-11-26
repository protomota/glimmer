import SwiftUI

struct PlanView: View {
    @State private var completionNote: String?
    @Environment(JournalStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let catalog: Catalog
    @State private var edit: PlanTask?
    @State private var quickName = ""
    @State private var showAll = false

    private var tasks: [PlanTask] { showAll ? store.journal.tasks : store.todaysTasks }
    private var count: Int { store.todaysTasks.filter { store.todayCompletion.contains($0.id) }.count }
    private var fraction: Double { Double(count) / Double(max(1, store.todaysTasks.count)) }

    var body: some View {
        Page(title: "One small task", subtitle: "Give today a shape that feels manageable.", width: 820) {
            progress
            Panel(padding: 10) {
                HStack {
                    Eyebrow(showAll ? "All scheduled tasks" : "Today")
                    Spacer()
                    Button(showAll ? "Show today" : "Show all") {
                        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { showAll.toggle() }
                    }
                    .buttonStyle(.plain).font(.subheadline).foregroundStyle(.secondary)
                    .frame(minHeight: 30).contentShape(.rect)
                    .accessibilityLabel(showAll ? "Show today’s tasks" : "Show all scheduled tasks")
                }
                .padding(.horizontal, 8).padding(.top, 4)
                VStack(spacing: 0) {
                    if tasks.isEmpty {
                        Text("Nothing scheduled yet. Write one small task below.")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 8)
                    }
                    ForEach(tasks) { task in
                        row(task)
                        Divider().padding(.leading, 52)
                    }
                    quickAdd
                }
                Button("New scheduled task", systemImage: "calendar.badge.plus") { edit = PlanTask() }
                    .buttonStyle(.plain).font(.subheadline).foregroundStyle(.secondary)
                    .frame(minHeight: 36).padding(.horizontal, 8).contentShape(.rect)
            }
            PersonalTodoList()
            Panel(title: "Ideas", plain: true) {
                VStack(spacing: 0) {
                    LinkRow(title: "Toolkit", detail: "Break to-dos down, size them and focus on one thing",
                            icon: "wrench.and.screwdriver", tint: GlimmerColor.sage) { ToolkitView() }
                        .accessibilityIdentifier("plan.toolkit")
                    LinkRow(title: "Plan my day with suggestions", detail: "A few small tasks to choose from",
                            icon: "sparkles", tint: GlimmerColor.honey) { PreloadView(catalog: catalog) }
                    LinkRow(title: "Browse the task library", detail: "\(catalog.library.count) categories",
                            icon: "books.vertical", tint: GlimmerColor.dusk) { TaskLibraryView(catalog: catalog) }
                }
            }
        }
        .sheet(item: $edit) { TaskEditor(task: $0) }
    }

    /// Where today stands: one line, the tracker and the coins. No box around it.
    private var progress: some View {
        let percent = Int((fraction * 100).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                if store.journal.tracker == .ring {
                    ZStack {
                        Circle().stroke(Color.primary.opacity(0.08), lineWidth: 8)
                        Circle().trim(from: 0, to: fraction)
                            .stroke(GlimmerColor.sage, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .opacity(fraction == 0 ? 0 : 1)
                            .animation(reduceMotion ? nil : .smooth(duration: 0.58), value: fraction)
                        Text("\(percent)%").font(.subheadline.monospacedDigit().weight(.semibold))
                            .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(percent)))
                            .animation(.easeOut(duration: reduceMotion ? 0.18 : 0.32), value: percent)
                    }
                    .frame(width: 60, height: 60)
                    .accessibilityHidden(true)
                }
                Text("\(count) of \(store.todaysTasks.count) complete").font(GlimmerFont.display(.title3))
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(count)))
                    .animation(.easeOut(duration: reduceMotion ? 0.18 : 0.32), value: count)
                Spacer(minLength: 0)
                CoinCount(count: store.journal.coins)
            }
            if store.journal.tracker != .ring { Meter(value: fraction, tint: GlimmerColor.sage) }
            // The praise line has its own place, so the list below never moves under a finger.
            Text(" ").font(.callout).frame(minHeight: 23).accessibilityHidden(true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) {
                    if let completionNote {
                        HStack(spacing: 7) {
                            GlimmerLogo(size: 23)
                            Text(completionNote).font(.callout).lineLimit(2)
                        }
                        .accessibilityElement(children: .combine)
                        .transition(reduceMotion
                                    ? .opacity.animation(.easeOut(duration: 0.18))
                                    : .opacity.combined(with: .offset(y: -6)))
                        .task(id: completionNote) {
                            try? await Task.sleep(for: .seconds(3))
                            if !Task.isCancelled { setCompletionNote(nil) }
                        }
                    }
                }
        }
        .padding(.horizontal, 2)
    }

    /// A task: the tick completes it, the rest of the line opens it.
    private func row(_ task: PlanTask) -> some View {
        let done = store.todayCompletion.contains(task.id)
        let today = task.occurs(on: store.day)
        return HStack(spacing: 0) {
            if today {
                TickButton(done: done, label: "\(done ? "Uncheck" : "Complete") \(task.name)") { toggle(task) }
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
            Button { edit = task } label: {
                HStack(spacing: 10) {
                    GlyphTile(Glyph.symbol(icon: task.icon, name: task.name, category: task.category),
                              tint: Glyph.tint(for: task.category))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(task.name).font(.body).multilineTextAlignment(.leading)
                        if showAll || task.schedule != Cadence.daily.rawValue {
                            Text(task.schedule).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(done ? Color.secondary : Color.primary)
                    Spacer(minLength: 6)
                }
                .padding(.leading, 2).padding(.trailing, 8)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint("Edit task")
        }
        .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.25), value: done)
    }

    /// Typing a line here adds it to the plan, like writing on the next row of a list.
    private var quickAdd: some View {
        let empty = quickName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 0) {
            AddMark()
            TextField("Quick add a task", text: $quickName).textFieldStyle(.plain).font(.body)
                .padding(.leading, 2)
                .frame(maxWidth: .infinity, minHeight: 52)
                .onSubmit(add)
            if !empty {
                Button("Add", action: add).glimmerButton(.prominent).padding(.trailing, 6)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: empty)
    }

    private func add() {
        let name = quickName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var task = PlanTask()
        task.name = name
        if store.change({ $0.tasks.append(task) }) { quickName = ""; store.notice = "Task added to your plan." }
    }

    private func toggle(_ task: PlanTask) {
        let wasDone = store.todayCompletion.contains(task.id)
        guard store.change({ $0.toggleTask(task, on: store.day) }) else { return }
        if wasDone {
            setCompletionNote(nil)
            return
        }
        let note = store.todaysTasks.allSatisfy { store.todayCompletion.contains($0.id) }
            ? "That’s your whole day. Rest easy."
            : catalog.praise.randomElement()
        setCompletionNote(note)
    }

    private func setCompletionNote(_ note: String?) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
            completionNote = note
        }
    }
}

struct TaskEditor: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var task: PlanTask
    @State private var delete = false
    private let icons = GlyphMap.taskIconPicker
    /// The task's current glyph, so a saved emoji icon shows (and stays selected) as its symbol.
    private var currentIcon: String { Glyph.symbol(icon: task.icon, name: task.name, category: task.category) }
    private var exists: Bool { store.journal.tasks.contains { $0.id == task.id } }

    var body: some View {
        NavigationStack {
            Page(title: task.name.isEmpty ? "New task" : "Edit task", width: 560) {
                Panel(title: "Task") {
                    TextField("Task name", text: $task.name).glimmerField()
                    Text("Icon").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(icons.contains(currentIcon) ? icons : [currentIcon] + icons, id: \.self) { icon in
                            Button { task.icon = icon } label: {
                                Image(systemName: icon).font(.body.weight(.semibold)).symbolRenderingMode(.monochrome)
                                    .frame(width: 30, height: 30)
                            }
                                .glimmerButton(currentIcon == icon ? .selected : .standard, circle: true)
                                .accessibilityLabel("Icon \(icon.replacingOccurrences(of: ".", with: " "))")
                                .accessibilityAddTraits(currentIcon == icon ? .isSelected : [])
                        }
                    }
                    .glassGroup(spacing: 6)
                }
                Panel(title: "Schedule", accent: GlimmerColor.sage) {
                    DatePicker(task.repeats ? "Starts" : "Date", selection: $task.anchor, displayedComponents: .date)
                    Toggle("Repeat", isOn: $task.repeats).toggleStyle(.switch)
                    if task.repeats {
                        GlassSegments(label: "Frequency", options: Cadence.allCases.map { GlassSegment(value: $0, title: $0.rawValue) },
                                      selection: $task.cadence)
                        Stepper("Every \(task.every) \(unit)", value: $task.every, in: 1...30)
                        if task.cadence == .weekly {
                            FlowLayout(spacing: 6) {
                                ForEach(1...7, id: \.self) { weekday in
                                    Chip(label: Calendar.current.shortWeekdaySymbols[weekday - 1],
                                         selected: task.weekdays.contains(weekday), tint: GlimmerColor.sage) {
                                        if task.weekdays.remove(weekday) == nil { task.weekdays.insert(weekday) }
                                    }
                                    .accessibilityLabel(Calendar.current.weekdaySymbols[weekday - 1])
                                }
                            }
                            .glassGroup(spacing: 6)
                        }
                    }
                }
            }
            .actionBar(width: 560) {
                SheetCancel { dismiss() }
                if exists {
                    Button(role: .destructive) { delete = true } label: {
                        Label("Delete task", systemImage: "trash").labelStyle(.iconOnly).frame(width: 22, height: 30)
                    }
                    .glimmerButton(.standard, circle: true).controlSize(.large)
                    .accessibilityLabel("Delete task")
                }
                PrimaryAction(title: "Save task", systemImage: "checkmark", action: save)
                    .disabled(task.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .sheetCancel { dismiss() }
        }
        .confirmationDialog("Remove this task from your plan?", isPresented: $delete) {
            Button("Delete task", role: .destructive) {
                if store.change({ $0.tasks.removeAll { $0.id == task.id } }) { dismiss() }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, idealWidth: 580, minHeight: 580, idealHeight: 640)
        #endif
    }

    private var unit: String {
        let name = task.cadence == .daily ? "day" : task.cadence == .weekly ? "week" : "month"
        return task.every == 1 ? name : name + "s"
    }

    private func save() {
        task.name = task.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.change({ journal in
            if let index = journal.tasks.firstIndex(where: { $0.id == task.id }) { journal.tasks[index] = task }
            else { journal.tasks.append(task) }
        }) { dismiss() }
    }
}

struct TaskLibraryView: View {
    @Environment(JournalStore.self) private var store
    let catalog: Catalog

    var body: some View {
        Page(title: "Task library", subtitle: "Pick what fits, skip the rest.", width: 900) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                ForEach(catalog.library) { category in
                    Panel {
                        GlyphTile(Glyph.symbol(icon: category.icon, name: category.name, category: category.id),
                                  tint: Glyph.tint(for: category.id), size: 44)
                        Text(category.name).font(GlimmerFont.display(.title3, weight: .bold))
                        Text(category.desc).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        LinkRow(title: "Browse \(category.tasks.count) tasks", tint: GlimmerColor.dusk) {
                            categoryPage(category)
                        }
                        .accessibilityLabel(category.name)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .navigationTitle("Task library")
    }

    private func categoryPage(_ category: TaskCategory) -> some View {
        Page(title: category.name, subtitle: category.desc) {
            Panel {
                VStack(spacing: 8) {
                    ForEach(category.tasks) { template in
                        let added = store.journal.tasks.contains { $0.id == template.id }
                        ActionRow(title: template.name, detail: added ? "In your plan · \(template.freq)" : template.freq,
                                  emoji: template.icon, tint: GlimmerColor.sage,
                                  trailing: added ? "checkmark.circle.fill" : "plus.circle", selected: added) {
                            store.change {
                                if added { $0.tasks.removeAll { $0.id == template.id } }
                                else { $0.tasks.append(PlanTask(template: template, category: category.id, date: store.day)) }
                            }
                        }
                    }
                }
                .glassGroup(spacing: 8)
            }
        }
    }
}

struct PreloadView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let catalog: Catalog
    @State private var selection: Set<String> = []

    var body: some View {
        Page(title: "Plan my day", kicker: "Start of day", subtitle: "A few suggestions. Pick what’s doable.") {
            VStack(spacing: 8) {
                ForEach(catalog.preload) { template in
                    let already = store.journal.tasks.contains { $0.id == template.id }
                    ActionRow(title: template.name, detail: already ? "Already in your plan" : template.freq,
                              emoji: template.icon, tint: GlimmerColor.sage,
                              selected: already || selection.contains(template.id),
                              tick: already || selection.contains(template.id)) {
                        if selection.remove(template.id) == nil { selection.insert(template.id) }
                    }
                    .disabled(already)
                }
            }
            .glassGroup(spacing: 8)
        }
        .actionBar {
            PrimaryAction(title: selection.isEmpty ? "Done" : "Add \(selection.count) to my plan") {
                if selection.isEmpty { dismiss(); return }
                if store.change({ journal in
                    let existing = Set(journal.tasks.map(\.id))
                    journal.tasks += catalog.preload.filter { selection.contains($0.id) && !existing.contains($0.id) }
                        .map { PlanTask(template: $0, date: store.day) }
                }) { store.notice = "Your day is set."; dismiss() }
            }
        }
        .onAppear { selection = Set(catalog.preload.map(\.id)).subtracting(store.journal.tasks.map(\.id)) }
    }
}
