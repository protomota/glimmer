import SwiftUI

/// What a to-do sheet is open for.
enum TodoTool: Identifiable {
    case breakDown(PersonalTodo, parent: TodoStep?)
    case timeCheck(PersonalTodo)
    case focus(PersonalTodo)

    var id: String {
        switch self {
        case .breakDown(let todo, let parent): "break-\(todo.id)-\(parent?.id.uuidString ?? "")"
        case .timeCheck(let todo): "time-\(todo.id)"
        case .focus(let todo): "focus-\(todo.id)"
        }
    }
}

extension View {
    /// Presents the Toolkit sheet for a to-do.
    /// One thing covers the whole screen on iPhone and iPad so nothing else competes for attention.
    func todoToolSheet(_ tool: Binding<TodoTool?>) -> some View {
        let sheetTool = Binding<TodoTool?>(
            get: { if case .focus = tool.wrappedValue { nil } else { tool.wrappedValue } },
            set: { tool.wrappedValue = $0 })
        let focusTodo = Binding<PersonalTodo?>(
            get: { if case .focus(let todo) = tool.wrappedValue { todo } else { nil } },
            set: { if $0 == nil { tool.wrappedValue = nil } })
        return sheet(item: sheetTool) { tool in
            switch tool {
            case .breakDown(let todo, let parent): BreakItDownSheet(todo: todo, parent: parent)
            case .timeCheck(let todo): TimeCheckSheet(todo: todo)
            case .focus(let todo): OneThingSheet(start: todo)
            }
        }
        #if os(iOS)
        .fullScreenCover(item: focusTodo) { OneThingSheet(start: $0) }
        #else
        .sheet(item: focusTodo) { OneThingSheet(start: $0) }
        #endif
    }
}

// MARK: - Break it down

struct BreakItDownPicker: View {
    @Environment(JournalStore.self) private var store
    @State private var tool: TodoTool?

    var body: some View {
        Page(title: "Break it down", subtitle: "Pick a to-do, and Glimmer suggests small steps you can edit before saving.", width: 620) {
            TodoChooser(prompt: "What feels heavy?", detail: detail) { tool = .breakDown($0, parent: nil) }
        }
        .todoToolSheet($tool)
    }

    private func detail(_ todo: PersonalTodo) -> String? {
        let steps = store.journal.steps(for: todo.id)
        guard !steps.isEmpty else { return nil }
        return "\(steps.filter(\.done).count) of \(steps.count) steps done"
    }
}

/// Suggests steps for a to-do, or smaller steps for one step. Nothing is saved until Save.
struct BreakItDownSheet: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StepSize.preference) private var stepSize = StepSize.balanced.rawValue
    let todo: PersonalTodo
    let parent: TodoStep?

    @State private var draft: [DraftStep] = []
    @State private var previous: [DraftStep]?
    @State private var result: (source: ToolkitSource, note: String?)?
    @State private var working: Task<Void, Never>?
    @State private var loaded = false

    private struct DraftStep: Identifiable, Equatable {
        let id = UUID()
        var title: String
    }

    private var cleanTitles: [String] {
        draft.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private var changed: Bool { cleanTitles != store.journal.steps(for: todo.id, parent: parent?.id).map(\.title) }

    var body: some View {
        NavigationStack {
            Page(title: parent?.title ?? todo.title,
                 subtitle: parent == nil ? "Steps you could start right now. Edit anything before you save."
                                         : "Smaller steps for this one step.", width: 560) {
                Panel(title: "Step size") { StepSizeControl(value: $stepSize) }
                if working != nil {
                    Panel { ToolkitThinking(text: thinkingText) }
                } else if !draft.isEmpty {
                    steps
                }
            }
            .actionBar(width: 560) {
                SheetCancel { dismiss() }
                if draft.isEmpty {
                    PrimaryAction(title: "Break it down", systemImage: "list.bullet.indent", action: generate)
                        .disabled(working != nil)
                        .accessibilityIdentifier("breakItDown.generate")
                } else {
                    Button("Try again", systemImage: "arrow.clockwise", action: generate)
                        .glimmerButton().controlSize(.large)
                        .disabled(working != nil)
                        .accessibilityIdentifier("breakItDown.again")
                    PrimaryAction(title: "Save steps", action: save)
                        .disabled(working != nil || cleanTitles.isEmpty || !changed)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("breakItDown.save")
                }
            }
            .sheetCancel { dismiss() }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            draft = store.journal.steps(for: todo.id, parent: parent?.id).map { DraftStep(title: $0.title) }
            #if DEBUG
            if ProcessInfo.processInfo.environment["GLIMMER_TOOLKIT_AUTORUN"] == "1" { generate() }
            #endif
        }
        .onDisappear { working?.cancel() }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 640)
        #endif
    }

    private var thinkingText: String {
        if let agent = ToolkitAI.agentChoice { return "Asking \(agent.agent.title)…" }
        return ToolkitAI.hasDeviceModel ? "Thinking on this device…" : "Finding steps…"
    }

    private var steps: some View {
        Panel(title: "Steps") {
            VStack(spacing: 6) {
                ForEach($draft) { $step in
                    let index = draft.firstIndex(of: step) ?? 0
                    HStack(spacing: 8) {
                        Text("\(index + 1)").font(.callout.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary)
                            .frame(minWidth: 22)
                            .accessibilityHidden(true)
                        TextField("Step", text: $step.title, axis: .vertical)
                            .textFieldStyle(.plain)
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .accessibilityLabel("Step \(index + 1)")
                        Menu {
                            Button("Move up", systemImage: "arrow.up") { move(index, by: -1) }.disabled(index == 0)
                            Button("Move down", systemImage: "arrow.down") { move(index, by: 1) }.disabled(index == draft.count - 1)
                            Button("Remove step", systemImage: "trash", role: .destructive) { draft.remove(at: index) }
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 32, height: 32).contentShape(.rect)
                        }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Options for step \(index + 1)")
                    }
                    if step.id != draft.last?.id { Divider().padding(.leading, 30) }
                }
            }
            HStack {
                Button("Add a step", systemImage: "plus") { draft.append(DraftStep(title: "")) }
                    .glimmerButton()
                    .accessibilityIdentifier("breakItDown.addStep")
                if let previous {
                    Button("Undo", systemImage: "arrow.uturn.backward") {
                        draft = previous
                        self.previous = nil
                        result = nil
                    }
                    .glimmerButton()
                }
            }
            if let result { ToolkitSourceLabel(source: result.source, note: result.note) }
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard draft.indices.contains(target) else { return }
        draft.swapAt(index, target)
    }

    private func generate() {
        let size = StepSize(rawValue: stepSize) ?? .balanced
        working = Task {
            let answer = await ToolkitAI.breakDown(todo.title, parent: parent?.title, size: size)
            guard !Task.isCancelled else { return }
            if !draft.isEmpty { previous = draft }
            draft = answer.value.map { DraftStep(title: $0) }
            result = (answer.source, answer.note)
            working = nil
            AccessibilityNotification.Announcement("\(draft.count) steps suggested").post()
        }
    }

    private func save() {
        guard store.journal.personalTodos?.contains(where: { $0.id == todo.id }) == true else {
            store.notice = "This to-do was removed."
            dismiss()
            return
        }
        if store.change({ $0.replaceSteps(for: todo.id, parent: parent?.id, with: cleanTitles) }) {
            store.notice = "Steps saved."
            dismiss()
        }
    }
}

/// A to-do's steps as a checklist, inside the to-do editor.
struct TodoStepsPanel: View {
    @Environment(JournalStore.self) private var store
    let todo: PersonalTodo
    @Binding var tool: TodoTool?
    @State private var offerComplete = false

    private var steps: [TodoStep] { store.journal.steps(for: todo.id) }
    private var estimate: TodoEstimate? { store.journal.estimate(for: todo.id) }

    var body: some View {
        Panel(title: "Steps") {
            if steps.isEmpty {
                Text("Big or vague? Break it into steps you could start right now.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(steps) { step in
                        row(step, level: 0)
                        ForEach(store.journal.steps(for: todo.id, parent: step.id)) { row($0, level: 1) }
                    }
                }
                .padding(.leading, -8)
            }
            FlowLayout(spacing: 8) {
                Button(steps.isEmpty ? "Break it down" : "Redo steps", systemImage: "list.bullet.indent") {
                    tool = .breakDown(todo, parent: nil)
                }
                .accessibilityIdentifier("todoSteps.breakDown")
                Button(estimate.map { "Time check · \(ToolkitFormat.chip($0.minutes))" } ?? "Time check", systemImage: "clock") {
                    tool = .timeCheck(todo)
                }
                .accessibilityIdentifier("todoSteps.timeCheck")
                if !todo.completed {
                    Button("One thing", systemImage: "scope") { tool = .focus(todo) }
                        .accessibilityIdentifier("todoSteps.focus")
                }
            }
            .glimmerButton()
        }
        .alert("All steps done", isPresented: $offerComplete) {
            Button("Complete to-do") { store.setPersonalTodoDone(todo.id, done: true) }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("Mark “\(todo.title)” complete?")
        }
    }

    private func row(_ step: TodoStep, level: Int) -> some View {
        HStack(spacing: 4) {
            TickButton(done: step.done, label: step.title, size: level == 0 ? 24 : 20) { toggle(step) }
                .accessibilityValue(step.done ? "Done" : "Not done")
                .accessibilityAddTraits(.isToggle)
            Text(step.title).font(level == 0 ? .body : .callout)
                .foregroundStyle(step.done ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            if level < TodoStep.maxLevels - 1 && !step.done {
                Button {
                    tool = .breakDown(todo, parent: step)
                } label: {
                    Image(systemName: "arrow.turn.down.right").font(.footnote.weight(.semibold))
                        .frame(width: 36, height: 36).contentShape(.rect)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Break this step down")
                .accessibilityLabel("Break “\(step.title)” down")
            }
        }
        .padding(.leading, CGFloat(level) * 28)
        .animation(.easeOut(duration: 0.2), value: step.done)
    }

    private func toggle(_ step: TodoStep) {
        guard store.change({ $0.setStepDone(step.id, done: !step.done) }) else { return }
        let all = store.journal.flatSteps(for: todo.id)
        if !step.done, !all.isEmpty, all.allSatisfy(\.done), !todo.completed { offerComplete = true }
    }
}

// MARK: - Time check

struct TimeCheckView: View {
    @Environment(JournalStore.self) private var store
    @State private var tool: TodoTool?

    private var dueTotal: Int {
        store.duePersonalTodos.compactMap { store.journal.estimate(for: $0.id)?.minutes }.reduce(0, +)
    }

    var body: some View {
        Page(title: "Time check", subtitle: "Realistic guesses, adjusted for how focused you feel today. Adjust any of them.", width: 620) {
            if dueTotal > 0 {
                Panel {
                    Text("About \(ToolkitFormat.minutes(dueTotal)) of to-dos due today")
                        .font(GlimmerFont.display(.title3, weight: .semibold))
                    Text("Leave room for breaks and the unexpected.").font(.callout).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            TodoChooser(prompt: "Add a to-do", detail: detail) { tool = .timeCheck($0) }
        }
        .todoToolSheet($tool)
    }

    private func detail(_ todo: PersonalTodo) -> String? {
        store.journal.estimate(for: todo.id).map { ToolkitFormat.chip($0.minutes) }
    }
}

struct TimeCheckSheet: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let todo: PersonalTodo
    @State private var chosenFocus: FocusLevel = .steady
    @State private var minutes: Int?
    @State private var source: ToolkitSource = .guide
    @State private var note: String?
    @State private var working: Task<Void, Never>?

    private var loggedFocus: FocusLevel? { store.todaysFocus }
    private var focus: FocusLevel { loggedFocus ?? chosenFocus }
    private var saved: TodoEstimate? { store.journal.estimate(for: todo.id) }

    var body: some View {
        NavigationStack {
            Page(title: todo.title, subtitle: "How long might this take you today?", width: 520) {
                Panel(title: "Focus") {
                    if let loggedFocus {
                        Label("From today’s energy check-in: \(loggedFocus.rawValue.lowercased())", systemImage: "bolt.heart")
                            .font(.callout)
                    } else {
                        Text("How focused do you feel?").font(.callout)
                        GlassSegments(label: "How focused do you feel?",
                                      options: FocusLevel.allCases.map { GlassSegment(value: $0, title: $0.rawValue) },
                                      selection: $chosenFocus)
                            .accessibilityIdentifier("timeCheck.focus")
                        Text(chosenFocus.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if working != nil {
                    Panel { ToolkitThinking(text: "Estimating…") }
                } else if let minutes {
                    Panel(title: "Estimate") {
                        Text(ToolkitFormat.chip(minutes))
                            .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                            .contentTransition(.numericText(value: Double(minutes)))
                            .accessibilityIdentifier("timeCheck.result")
                        Stepper("Adjust", value: Binding(get: { minutes }, set: { self.minutes = $0; source = .person; note = nil }),
                                in: 5...600, step: 5)
                            .accessibilityValue(ToolkitFormat.minutes(minutes))
                        ToolkitSourceLabel(source: source, note: note)
                    }
                }
            }
            .actionBar(width: 520) {
                SheetCancel { dismiss() }
                if saved != nil {
                    Button("Clear estimate", systemImage: "xmark") {
                        if store.change({ $0.setEstimate(nil, source: "", for: todo.id) }) { dismiss() }
                    }
                    .labelStyle(.iconOnly).glimmerButton().controlSize(.large)
                }
                if minutes == nil {
                    PrimaryAction(title: "Check time", systemImage: "clock", action: estimate)
                        .disabled(working != nil)
                        .accessibilityIdentifier("timeCheck.estimate")
                } else {
                    Button("Again", systemImage: "arrow.clockwise", action: estimate)
                        .glimmerButton().controlSize(.large).disabled(working != nil)
                    PrimaryAction(title: "Save", action: save)
                        .disabled(working != nil)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("timeCheck.save")
                }
            }
            .sheetCancel { dismiss() }
        }
        .onAppear {
            if let saved {
                minutes = saved.minutes
                source = ToolkitSource(rawValue: saved.source) ?? .guide
            }
            #if DEBUG
            if ProcessInfo.processInfo.environment["GLIMMER_TOOLKIT_AUTORUN"] == "1" { estimate() }
            #endif
        }
        .onDisappear { working?.cancel() }
        #if os(macOS)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 460)
        #endif
    }

    private func estimate() {
        let steps = store.journal.flatSteps(for: todo.id).filter { !$0.done }.map(\.title)
        let level = focus
        working = Task {
            let answer = await ToolkitAI.estimate(todo.title, steps: steps, focus: level)
            guard !Task.isCancelled else { return }
            minutes = answer.value
            source = answer.source
            note = answer.note
            working = nil
            AccessibilityNotification.Announcement("About \(ToolkitFormat.minutes(answer.value))").post()
        }
    }

    private func save() {
        guard let minutes else { return }
        if store.change({ $0.setEstimate(minutes, source: source.rawValue, for: todo.id) }) {
            store.notice = "Estimate saved."
            dismiss()
        }
    }
}
