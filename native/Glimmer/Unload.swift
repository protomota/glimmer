import SwiftUI

/// Unload: a brain dump becomes a reviewed list of personal to-dos.
struct UnloadView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readingTheme) private var theme
    @AppStorage(StepSize.preference) private var stepSize = StepSize.balanced.rawValue
    @SceneStorage("glimmer.toolkit.unload") private var text = ""
    @State private var items: [UnloadItem] = []
    @State private var result: (source: ToolkitSource, note: String?)?
    @State private var breakEachDown = false
    @State private var working: Task<Void, Never>?
    @State private var progress: String?

    private var chosen: [UnloadItem] {
        items.filter { $0.included && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        Page(title: "Unload", subtitle: "Get it all out of your head. Glimmer sorts it into to-dos you can check before anything is added.", width: 620) {
            if items.isEmpty {
                Panel {
                    ToolkitTextEditor(text: $text, prompt: "Everything on your mind, in any order…", minHeight: 220)
                        .accessibilityIdentifier("unload.text")
                    Text("Lists, half-sentences and “oh and also” are all fine.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let progress { Panel { ToolkitThinking(text: progress) } }
            } else {
                review
            }
        }
        .actionBar(width: 620) {
            if items.isEmpty {
                PrimaryAction(title: "Sort it out", systemImage: "tray.and.arrow.down", action: sort)
                    .disabled(working != nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("unload.sort")
            } else {
                Button("Start over", systemImage: "arrow.uturn.backward") {
                    items = []
                    result = nil
                }
                .glimmerButton().controlSize(.large).disabled(working != nil)
                PrimaryAction(title: chosen.count == 1 ? "Add 1 to-do" : "Add \(chosen.count) to-dos", action: add)
                    .disabled(working != nil || chosen.isEmpty)
                    .accessibilityIdentifier("unload.add")
            }
        }
        .onDisappear { working?.cancel() }
        #if DEBUG
        .onAppear {
            if let sample = ProcessInfo.processInfo.environment["GLIMMER_UNLOAD_TEXT"], items.isEmpty {
                text = sample.replacingOccurrences(of: "|", with: "\n")
                if ProcessInfo.processInfo.environment["GLIMMER_TOOLKIT_AUTORUN"] == "1" { sort() }
            }
        }
        #endif
    }

    private var review: some View {
        Group {
            Panel(title: "To-dos") {
                VStack(spacing: 0) {
                    ForEach($items) { $item in
                        HStack(spacing: 2) {
                            TickButton(done: item.included, label: item.included ? "Include \(item.title)" : "Skip \(item.title)",
                                       tint: theme.selectionInk, onTint: theme.selectionOnInk, completes: false) {
                                item.included.toggle()
                            }
                            .accessibilityValue(item.included ? "Included" : "Skipped")
                            TextField("To-do", text: $item.title, axis: .vertical)
                                .textFieldStyle(.plain)
                                .foregroundStyle(item.included ? .primary : .secondary)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            if let due = item.dueDay, let date = PracticeDate.parse(due) {
                                Menu {
                                    Button("Remove due date", systemImage: "calendar.badge.minus") { item.dueDay = nil }
                                } label: {
                                    Text(dueLabel(due, date)).font(.footnote.weight(.medium))
                                        .padding(.horizontal, 9).padding(.vertical, 4)
                                        .background(Color.primary.opacity(0.07), in: .capsule)
                                }
                                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                                .accessibilityLabel("Due \(dueLabel(due, date))")
                            }
                        }
                        Divider().opacity(0.6).padding(.leading, 46)
                    }
                    Button { items.append(UnloadItem(title: "")) } label: {
                        HStack(spacing: 2) {
                            AddMark()
                            Text("Add another").foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityLabel("Add another")
                }
                .padding(.leading, -8)
                if let result { ToolkitSourceLabel(source: result.source, note: result.note) }
            }
            Panel {
                Toggle("Break each one down too", isOn: $breakEachDown).toggleStyle(.switch)
                    .accessibilityIdentifier("unload.breakDown")
                if breakEachDown {
                    Text("Uses your step size: \((StepSize(rawValue: stepSize) ?? .balanced).title.lowercased()).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let progress { ToolkitThinking(text: progress) }
            }
        }
    }

    private func dueLabel(_ day: String, _ date: Date) -> String {
        if day == PracticeDate.key(store.day) { return "Today" }
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: store.day), day == PracticeDate.key(tomorrow) {
            return "Tomorrow"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private func sort() {
        let dump = text
        let today = store.day
        progress = ToolkitAI.agentChoice.map { "Asking \($0.agent.title)…" } ?? "Sorting…"
        working = Task {
            let answer = await ToolkitAI.unload(dump, today: today)
            guard !Task.isCancelled else { return }
            items = answer.value
            result = (answer.source, answer.note)
            progress = nil
            working = nil
            if items.isEmpty { store.notice = "Couldn’t find any to-dos in that. Try one per line." }
            AccessibilityNotification.Announcement("\(items.count) to-dos found").post()
        }
    }

    private func add() {
        let todos = chosen.map {
            PersonalTodo(title: String($0.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(PersonalTodo.titleLimit)),
                         dueDay: $0.dueDay)
        }
        guard store.change({ $0.personalTodos = ($0.personalTodos ?? []) + todos }) else { return }
        let size = StepSize(rawValue: stepSize) ?? .balanced
        guard breakEachDown else { finish(todos.count) ; return }
        working = Task {
            for (index, todo) in todos.enumerated() {
                progress = "Breaking down \(index + 1) of \(todos.count)…"
                let steps = await ToolkitAI.breakDown(todo.title, size: size)
                if Task.isCancelled { break }
                store.change { $0.replaceSteps(for: todo.id, with: steps.value) }
            }
            progress = nil
            working = nil
            finish(todos.count)
        }
    }

    private func finish(_ count: Int) {
        items = []
        result = nil
        text = ""
        store.notice = count == 1 ? "1 to-do added to your plan." : "\(count) to-dos added to your plan."
    }
}
