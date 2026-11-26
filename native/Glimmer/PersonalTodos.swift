import SwiftUI

struct PersonalTodoList: View {
    @Environment(JournalStore.self) private var store
    @State private var editing: PersonalTodo?
    @State private var tool: TodoTool?
    var openPlan: (() -> Void)? = nil

    private var isToday: Bool { openPlan != nil }
    private var ordered: [PersonalTodo] { PersonalTodo.ordered(store.journal.personalTodos ?? []) }
    private var open: [PersonalTodo] { ordered.filter { !$0.completed } }
    private var completed: [PersonalTodo] { ordered.filter(\.completed) }

    var body: some View {
        Group {
            if isToday {
                if !store.duePersonalTodos.isEmpty {
                    Panel(title: "Personal to-dos") {
                        rows(Array(store.duePersonalTodos.prefix(4)))
                        if store.duePersonalTodos.count > 4, let openPlan {
                            SecondaryAction(title: "All to-dos", systemImage: "chevron.right", action: openPlan)
                        }
                    }
                }
            } else {
                Panel(title: "Personal to-dos") {
                    if open.isEmpty { Text("No open to-dos.").font(.callout).foregroundStyle(.secondary) }
                    if dueMinutes > 0 {
                        Label("About \(ToolkitFormat.minutes(dueMinutes)) of to-dos due today", systemImage: "clock")
                            .font(.callout).foregroundStyle(.secondary)
                            .accessibilityIdentifier("personalTodos.dueTotal")
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        rows(open)
                        if !open.isEmpty { Divider().padding(.leading, 44) }
                        Button { editing = PersonalTodo() } label: {
                            HStack(spacing: 0) {
                                AddMark()
                                Text("Add to-do").foregroundStyle(.secondary).padding(.leading, 2)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(RowPressStyle())
                        .padding(.leading, -8)
                        .accessibilityLabel("Add to-do")
                        .accessibilityIdentifier("personalTodos.add")
                    }
                    FlowLayout(spacing: 8) {
                        NavigationLink { UnloadView().hidesTabBar() } label: {
                            Label("Unload", systemImage: "tray.and.arrow.down").fontWeight(.medium)
                                .frame(minHeight: 24)
                        }
                        .glimmerButton().buttonBorderShape(.capsule)
                        .accessibilityHint("Turn a brain dump into to-dos")
                        .accessibilityIdentifier("personalTodos.unload")
                        if !open.isEmpty {
                            NavigationLink { OneThingView() } label: {
                                Label("One thing", systemImage: "scope").fontWeight(.medium)
                                    .frame(minHeight: 24)
                            }
                            .glimmerButton().buttonBorderShape(.capsule)
                            .accessibilityHint("Focus on the next step of one to-do")
                            .accessibilityIdentifier("personalTodos.oneThing")
                        }
                    }
                    if !completed.isEmpty {
                        Divider()
                        DisclosureGroup("Completed (\(completed.count))") { rows(completed) }
                            .accessibilityIdentifier("personalTodos.completed")
                    }
                    if store.usesDeviceReminders { reminderStatus }
                }
            }
        }
        .sheet(item: $editing) { PersonalTodoEditor(task: $0, today: store.day) }
        .todoToolSheet($tool)
    }

    private var dueMinutes: Int {
        store.duePersonalTodos.compactMap { store.journal.estimate(for: $0.id)?.minutes }.reduce(0, +)
    }

    @ViewBuilder private var reminderStatus: some View {
        let reminders = PersonalReminders.shared
        if open.contains(where: { $0.reminderAt.map { $0 > .now } == true }) {
            if reminders.authorization == .notDetermined {
                SecondaryAction(title: "Enable notifications", systemImage: "bell") {
                    Task {
                        _ = await reminders.authorize()
                        reminders.refresh(store.journal.personalTodos ?? [])
                    }
                }
            } else if reminders.authorization == .denied {
                Text("Turn on Glimmer notifications in system settings to receive reminders here.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if reminders.schedulingFailed {
                Text("Glimmer couldn’t schedule a reminder on this device.").font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rows(_ tasks: [PersonalTodo]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tasks) { task in
                if task.id != tasks.first?.id { Divider().padding(.leading, 52) }
                PersonalTodoRow(task: task, edit: { editing = task }, use: { tool = $0 })
            }
        }
        // The tick sits in a 44 point target; pull it out so the mark lines up with the heading.
        .padding(.leading, -8)
    }
}

private struct PersonalTodoRow: View {
    @Environment(JournalStore.self) private var store
    let task: PersonalTodo
    let edit: () -> Void
    let use: (TodoTool) -> Void

    private var steps: [TodoStep] { store.journal.flatSteps(for: task.id) }
    private var estimate: Int? { store.journal.estimate(for: task.id)?.minutes }
    private var toolkitLabel: String? {
        var parts: [String] = []
        if !steps.isEmpty { parts.append("\(steps.filter(\.done).count) of \(steps.count) steps") }
        if let estimate, !task.completed { parts.append(ToolkitFormat.chip(estimate)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var today: String { PracticeDate.key(store.day) }
    private var dueLabel: String? {
        guard let due = task.dueDay, let date = PracticeDate.parse(due) else { return nil }
        if due == today { return "Due today" }
        let label = date.formatted(.dateTime.month(.abbreviated).day())
        return due < today && !task.completed ? "Overdue · \(label)" : "Due \(label)"
    }

    var body: some View {
        HStack(spacing: 0) {
            TickButton(done: task.completed, label: "\(task.completed ? "Reopen" : "Complete") \(task.title)") {
                store.setPersonalTodoDone(task.id, done: !task.completed)
            }

            Button(action: edit) {
                HStack(spacing: 10) {
                    GlyphTile(Glyph.symbol(name: task.title, category: "todo"), tint: Glyph.tint(for: "todo"))
                    VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(.body).foregroundStyle(task.completed ? Color.secondary : Color.primary)
                    if dueLabel != nil || toolkitLabel != nil {
                        HStack(spacing: 6) {
                            if let dueLabel {
                                Text(dueLabel)
                                    .foregroundStyle(task.dueDay.map { $0 < today && !task.completed } == true
                                                     ? GlimmerColor.ember : Color.secondary)
                            }
                            if dueLabel != nil && toolkitLabel != nil { Text("·").foregroundStyle(.secondary) }
                            if let toolkitLabel { Text(toolkitLabel).foregroundStyle(.secondary) }
                        }
                        .font(.footnote)
                    }
                }
                }
                .padding(.leading, 2)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(.rect)
                .multilineTextAlignment(.leading)
            }
            .buttonStyle(RowPressStyle())
            .accessibilityHint("Edit to-do")

            if let reminder = task.reminderAt, reminder > .now, !task.completed {
                Image(systemName: "bell").font(.footnote).foregroundStyle(.secondary)
                    .accessibilityLabel("Reminder \(reminder.formatted(date: .abbreviated, time: .shortened))")
            }
            if !task.completed {
                Menu {
                    Button("Break it down", systemImage: "list.bullet.indent") { use(.breakDown(task, parent: nil)) }
                    Button("Time check", systemImage: "clock") { use(.timeCheck(task)) }
                    Button("One thing", systemImage: "scope") { use(.focus(task)) }
                } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.medium))
                        .frame(width: 36, height: 44).contentShape(.rect)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Toolkit for \(task.title)")
                .accessibilityIdentifier("personalTodos.tools")
            }
        }
    }
}

struct PersonalTodoEditor: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readingTheme) private var theme
    @State private var title: String
    @State private var hasDue: Bool
    @State private var due: Date
    @State private var hasReminder: Bool
    @State private var reminder: Date
    @State private var showingCalendar = false
    @State private var confirmDelete = false
    @State private var saving = false
    @State private var tool: TodoTool?
    let task: PersonalTodo

    init(task: PersonalTodo, today: Date) {
        self.task = task
        _title = State(initialValue: task.title)
        _hasDue = State(initialValue: task.dueDay != nil)
        _due = State(initialValue: task.dueDay.flatMap(PracticeDate.parse) ?? today)
        _hasReminder = State(initialValue: task.reminderAt != nil)
        let nextMinute = Date(timeIntervalSince1970: ceil(Date.now.timeIntervalSince1970 / 60) * 60 + 60)
        _reminder = State(initialValue: task.reminderAt ?? nextMinute)
    }

    private var exists: Bool { !task.title.isEmpty }
    private var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var validReminder: Bool { !hasReminder || reminder > .now || reminder == task.reminderAt }

    var body: some View {
        NavigationStack {
            Page(title: exists ? "Edit to-do" : "New to-do", width: 460) {
                Panel {
                    TextField("What do you need to do?", text: $title).glimmerField()
                        .accessibilityIdentifier("personalTodos.title")
                    if cleanTitle.count > PersonalTodo.titleLimit {
                        Text("Use 160 characters or fewer.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Panel {
                    Toggle("Due date", isOn: $hasDue).toggleStyle(.switch)
                    if hasDue {
                        Button {
                            showingCalendar = true
                        } label: {
                            Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        }
                        .glimmerButton()
                        .accessibilityIdentifier("personalTodos.dueDate")
                        .popover(isPresented: $showingCalendar) {
                            VStack(alignment: .trailing, spacing: 8) {
                                GlimmerCalendarGrid(selection: $due)
                                Button("Done") { showingCalendar = false }.glimmerButton(.prominent)
                            }
                            .padding(16)
                            .frame(idealWidth: 320, maxWidth: 360)
                            .background(theme.surface)
                        }
                    }
                    Divider()
                    Toggle("Remind me", isOn: $hasReminder).toggleStyle(.switch)
                    if hasReminder {
                        DatePicker("Reminder time", selection: $reminder).tint(theme.selectionInk)
                            .accessibilityIdentifier("personalTodos.reminderAt")
                        Text(validReminder ? "Alerts on this device when notifications are enabled." : "Choose a future time.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if exists, let current = store.journal.personalTodos?.first(where: { $0.id == task.id }) {
                    TodoStepsPanel(todo: current, tool: $tool)
                }
            }
            .actionBar(width: 460) {
                SheetCancel { dismiss() }
                if exists {
                    Button("Delete to-do", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        .labelStyle(.iconOnly).glimmerButton()
                }
                PrimaryAction(title: "Save", action: save)
                    .disabled(saving || !(1...PersonalTodo.titleLimit).contains(cleanTitle.count) || !validReminder)
                    .accessibilityIdentifier("personalTodos.save")
                    .keyboardShortcut(.defaultAction)
            }
            .sheetCancel { dismiss() }
        }
        .confirmationDialog("Delete this personal to-do?", isPresented: $confirmDelete) {
            Button("Delete to-do", role: .destructive) {
                if store.change({ $0.removePersonalTodo(task.id) }) { dismiss() }
            }
        }
        .todoToolSheet($tool)
        .interactiveDismissDisabled(saving)
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 440)
        #endif
    }

    private func save() {
        var saved = task
        saved.title = cleanTitle
        saved.dueDay = hasDue ? PracticeDate.key(due) : nil
        saved.reminderAt = hasReminder ? reminder : nil
        var found = !exists
        guard store.change({ journal in
            var tasks = journal.personalTodos ?? []
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                found = true
                saved.completed = tasks[index].completed
                tasks[index] = saved
            } else if !exists {
                tasks.append(saved)
            }
            journal.personalTodos = tasks
        }), found else {
            if !found { store.notice = "This to-do was removed." }
            return
        }
        guard store.usesDeviceReminders, hasReminder, !saved.completed, reminder > .now else { dismiss(); return }
        saving = true
        Task {
            if await PersonalReminders.shared.authorize() {
                PersonalReminders.shared.refresh(store.journal.personalTodos ?? [])
            } else {
                store.notice = "To-do saved. Turn on Glimmer notifications in system settings for reminders."
            }
            dismiss()
        }
    }
}
