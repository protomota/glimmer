import SwiftUI

/// One thing: pick a to-do, then see only its next step with a gentle timer.
struct OneThingView: View {
    @Environment(JournalStore.self) private var store
    @State private var tool: TodoTool?
    @State private var showAll = false

    var body: some View {
        Page(title: "One thing", subtitle: "Just the next step, with a gentle timer. Everything else can wait.", width: 620) {
            OneThingChoices { tool = .focus($0) }
            if store.openPersonalTodos.count > 2 {
                Panel(title: "Something else", plain: true) {
                    DisclosureGroup("All open to-dos (\(store.openPersonalTodos.count))", isExpanded: $showAll) {
                        VStack(spacing: 8) {
                            ForEach(store.openPersonalTodos) { todo in
                                ActionRow(title: todo.title, tint: GlimmerColor.sage) { tool = .focus(todo) }
                            }
                        }
                        .glassGroup(spacing: 8)
                        .padding(.top, 6)
                    }
                }
            }
        }
        .todoToolSheet($tool)
        .hidesTabBar()
    }
}

/// "What next?": two suggestions, chosen by due date, size and how focused the person feels.
struct OneThingChoices: View {
    @Environment(JournalStore.self) private var store
    var excluding: UUID? = nil
    let choose: (PersonalTodo) -> Void

    private var choices: [PersonalTodo] {
        OneThingPicker.choices(store.openPersonalTodos.filter { $0.id != excluding },
                               estimates: store.journal.todoEstimates ?? [],
                               focus: store.todaysFocus ?? .steady, today: PracticeDate.key(store.day),
                               hour: Calendar.current.component(.hour, from: .now))
    }

    var body: some View {
        Panel(title: "What next?", plain: true) {
            if choices.isEmpty {
                Text("No open to-dos. Add one in Plan, or use Unload to empty your head.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(choices) { todo in
                        ActionRow(title: todo.title, detail: reason(todo), icon: Glyph.symbol(name: todo.title, category: "todo"), tint: Glyph.tint(for: "todo")) { choose(todo) }
                            .accessibilityIdentifier("oneThing.choice")
                    }
                }
                .glassGroup(spacing: 8)
                Text(choices.count == 2 ? "Two options. Pick whichever feels doable." : "Pick it when you’re ready.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    static func dueLabel(_ due: String, today: String) -> String {
        if due < today { return "Overdue" }
        if due == today { return "Due today" }
        guard let date = PracticeDate.parse(due), let start = PracticeDate.parse(today),
              let days = Calendar.current.dateComponents([.day], from: start, to: date).day else { return "Due later" }
        if days == 1 { return "Due tomorrow" }
        return days < 7 ? "Due \(date.formatted(.dateTime.weekday(.wide)))" : "Due \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func reason(_ todo: PersonalTodo) -> String? {
        var parts: [String] = []
        let today = PracticeDate.key(store.day)
        if let due = todo.dueDay { parts.append(Self.dueLabel(due, today: today)) }
        if let minutes = store.journal.estimate(for: todo.id)?.minutes { parts.append(ToolkitFormat.chip(minutes)) }
        if let step = store.journal.nextStep(for: todo.id) { parts.append("Next: \(step.title)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The focus card for one to-do.
struct OneThingSheet: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var todoID: UUID
    @State private var skipped: Set<UUID> = []
    @State private var deadline: Date?
    @State private var timerMinutes = 10
    @State private var finished = false
    @State private var timeUp = false
    @State private var breakdown: TodoTool?

    init(start: PersonalTodo) {
        _todoID = State(initialValue: start.id)
    }

    private var todo: PersonalTodo? { store.journal.personalTodos?.first { $0.id == todoID } }
    private var allSteps: [TodoStep] { store.journal.flatSteps(for: todoID) }
    private var current: TodoStep? { store.journal.nextStep(for: todoID, skipping: skipped) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let todo {
                        if finished || todo.completed { done(todo) } else { focus(todo) }
                    } else {
                        ContentUnavailableView("This to-do was removed", systemImage: "checklist")
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 72).padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .background { PageBackdrop() }
            .sheetCancel { dismiss() }
            .actionBar(width: 560) { actions }
        }
        .sheet(item: $breakdown) { tool in
            if case .breakDown(let todo, let parent) = tool { BreakItDownSheet(todo: todo, parent: parent) }
        }
        .onAppear {
            if let minutes = store.journal.estimate(for: todoID)?.minutes {
                let remaining = max(1, allSteps.filter { !$0.done }.count)
                timerMinutes = min(25, max(5, minutes / remaining / 5 * 5))
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 520, idealHeight: 620)
        #endif
    }

    // MARK: Focus

    @ViewBuilder private func focus(_ todo: PersonalTodo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(todo.title).font(.headline).foregroundStyle(.secondary)
            if !allSteps.isEmpty {
                let doneCount = allSteps.filter(\.done).count
                StepDots(current: doneCount - 1, total: allSteps.count, tint: GlimmerColor.sage)
                Text("\(doneCount) of \(allSteps.count) steps done").font(.footnote).foregroundStyle(.secondary)
            }
        }
        VStack(alignment: .leading, spacing: 10) {
            Text(current == nil ? "Now" : "Next step").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(current?.title ?? todo.title)
                .font(GlimmerFont.reading(.largeTitle, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: current?.id)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("oneThing.step")
            if !skipped.isEmpty {
                Button("Bring back skipped steps", systemImage: "arrow.uturn.backward") { skipped = [] }
                    .font(.callout).buttonStyle(.borderless)
            }
        }
        timer
    }

    private var timer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let end = deadline {
                FocusCountdown(end: end, totalMinutes: timerMinutes) {
                    timeUp = true
                    deadline = nil
                }
                Button("Stop timer", systemImage: "stop.fill") { deadline = nil }.glimmerButton()
            } else {
                if timeUp {
                    Text("Time’s up. Keep going if it’s flowing, or take a short break.").font(.callout)
                }
                HStack(spacing: 12) {
                    Button("Start timer", systemImage: "timer") {
                        timeUp = false
                        deadline = .now.addingTimeInterval(Double(timerMinutes) * 60)
                    }
                    .glimmerButton()
                    .accessibilityIdentifier("oneThing.timer")
                    Stepper(value: $timerMinutes, in: 5...60, step: 5) {
                        Text("\(timerMinutes) min").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    .accessibilityLabel("Timer length")
                    .accessibilityValue("\(timerMinutes) minutes")
                }
            }
        }
        .padding(.top, 8)
        .sensoryFeedback(.success, trigger: timeUp) { _, new in new }
        // Each finished step lands with a tap you can feel.
        .sensoryFeedback(.success, trigger: allSteps.filter(\.done).count) { old, new in new > old }
    }

    @ViewBuilder private var actions: some View {
        if let todo, !(finished || todo.completed) {
            SheetCancel(title: "Close") { dismiss() }
            Menu {
                if let current {
                    Button("Skip this step", systemImage: "forward") { skipped.insert(current.id) }
                    if current.parentID == nil {
                        Button("Break this step down", systemImage: "list.bullet.indent") {
                            breakdown = .breakDown(todo, parent: current)
                        }
                    }
                } else {
                    Button("Break it down", systemImage: "list.bullet.indent") { breakdown = .breakDown(todo, parent: nil) }
                }
                Button("Pick something else", systemImage: "arrow.triangle.swap") { finished = true }
            } label: {
                Label("More", systemImage: "ellipsis").labelStyle(.iconOnly).frame(width: 22, height: 30)
            }
            .menuStyle(.button).menuIndicator(.hidden)
            .glimmerButton(.standard, circle: true).controlSize(.large)
            .accessibilityLabel("More options")
            .accessibilityIdentifier("oneThing.more")
            PrimaryAction(title: current == nil ? "Done with this to-do" : "Done", systemImage: "checkmark", action: complete)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("oneThing.done")
        } else {
            PrimaryAction(title: "Close") { dismiss() }
        }
    }

    private func complete() {
        deadline = nil
        timeUp = false
        if let current {
            store.change { $0.setStepDone(current.id, done: true) }
            if store.journal.nextStep(for: todoID, skipping: skipped) == nil,
               store.journal.flatSteps(for: todoID).allSatisfy(\.done) {
                store.setPersonalTodoDone(todoID, done: true)
                finished = true
            }
        } else {
            store.setPersonalTodoDone(todoID, done: true)
            finished = true
        }
    }

    // MARK: Done

    @ViewBuilder private func done(_ todo: PersonalTodo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if todo.completed {
                Label("Done", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(GlimmerColor.sage)
            }
            Text(todo.completed ? todo.title : "Pick something else")
                .font(GlimmerFont.reading(.largeTitle, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Text(todo.completed ? "That’s one thing finished. Rest, or pick the next." : "No problem. Here are two other options.")
                .foregroundStyle(.secondary)
        }
        .completionLight(todo.completed, radius: 12)
        OneThingChoices(excluding: todo.id) { next in
            todoID = next.id
            skipped = []
            finished = false
        }
    }
}

/// A quiet countdown that calls `finished` once when it reaches zero.
private struct FocusCountdown: View {
    let end: Date
    let totalMinutes: Int
    let finished: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            let seconds = max(0, Int(ceil(end.timeIntervalSince(tick.date))))
            VStack(alignment: .leading, spacing: 10) {
                Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                    .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityLabel("\(seconds / 60) minutes \(seconds % 60) seconds left")
                Meter(value: 1 - Double(seconds) / Double(max(1, totalMinutes * 60)), tint: GlimmerColor.honey)
            }
            .onChange(of: seconds == 0) { _, done in if done { finished() } }
        }
    }
}
