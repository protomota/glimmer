import SwiftUI

/// The Toolkit: small helpers for starting, sizing, focusing, saying and deciding.
struct ToolkitView: View {
    @Environment(JournalStore.self) private var store
    @AppStorage(StepSize.preference) private var stepSize = StepSize.balanced.rawValue

    var body: some View {
        Page(title: "Toolkit", subtitle: "Small helpers for when your mind is busy. Use one, then get back to your day.", width: 720) {
            section("Get started") {
                LinkRow(title: "Unload", detail: "Empty your head. Glimmer sorts it into to-dos",
                        icon: "tray.and.arrow.down.fill", tint: GlimmerColor.sage) { UnloadView().hidesTabBar() }
                    .accessibilityIdentifier("toolkit.unload")
                LinkRow(title: "Break it down", detail: "Turn one heavy to-do into steps you could start now",
                        icon: "list.bullet.indent", tint: GlimmerColor.sage) { BreakItDownPicker().hidesTabBar() }
                    .accessibilityIdentifier("toolkit.breakItDown")
            }
            section("Get it done") {
                LinkRow(title: "Time check", detail: "A kind guess at how long things take today",
                        icon: "clock.fill", tint: GlimmerColor.accent) { TimeCheckView().hidesTabBar() }
                    .accessibilityIdentifier("toolkit.timeCheck")
                LinkRow(title: "One thing", detail: "See only the next step, with a gentle timer",
                        icon: "scope", tint: GlimmerColor.accent) { OneThingView().hidesTabBar() }
                    .accessibilityIdentifier("toolkit.oneThing")
            }
            section("Say it") {
                LinkRow(title: "Read the room", detail: "How a message might come across, before you reply",
                        icon: "eye.fill", tint: GlimmerColor.dusk) { ReadTheRoomView().hidesTabBar() }
                    .accessibilityIdentifier("toolkit.readTheRoom")
                LinkRow(title: "Reword", detail: "The same message, kinder, clearer or shorter",
                        icon: "wand.and.sparkles", tint: GlimmerColor.dusk) { RewordView().hidesTabBar() }
                    .accessibilityIdentifier("toolkit.reword")
            }
            section("Decide") {
                LinkRow(title: "Weigh it", detail: "Pros, cons and a small experiment to find out",
                        icon: "scalemass.fill", tint: GlimmerColor.honey) { WeighItView().hidesTabBar() }
                    .accessibilityIdentifier("toolkit.weighIt")
            }
            Panel(title: "Step size") {
                StepSizeControl(value: $stepSize)
                Text("Sets how small Break it down and Unload make things, and how much Reword changes.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(ToolkitAI.routeSummary, systemImage: ToolkitAI.hasDeviceModel || ToolkitAI.agentChoice != nil ? "lock" : "book.closed")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        Panel(title: title, plain: true) {
            VStack(spacing: 8) { content() }.glassGroup(spacing: 8)
        }
    }
}

// MARK: - Shared controls

/// Five stepping stones, large to small. Picking one sets how fine-grained the Toolkit gets.
struct StepSizeControl: View {
    @Binding var value: Int
    @Environment(\.readingTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var size: StepSize { StepSize(rawValue: value) ?? .balanced }

    private var chosenTitle: some View {
        Text(size.title).font(.callout.weight(.semibold)).foregroundStyle(.primary)
            .contentTransition(.opacity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 0) {
                ForEach(StepSize.allCases) { option in
                    let diameter = CGFloat(30 - (option.rawValue - 1) * 5)
                    let chosen = option == size
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.2)) { value = option.rawValue }
                    } label: {
                        Circle()
                            .fill(option.rawValue <= size.rawValue ? theme.selectionInk.opacity(chosen ? 1 : 0.35)
                                                                    : Color.primary.opacity(0.10))
                            .overlay { Circle().strokeBorder(Color.primary.opacity(chosen ? 0 : 0.12), lineWidth: 1) }
                            .frame(width: diameter, height: diameter)
                            .scaleEffect(chosen && !reduceMotion ? 1.08 : 1)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Big strides")
                    Spacer()
                    chosenTitle
                    Spacer()
                    Text("Tiny steps")
                }
                .lineLimit(1)
                // Large text: the chosen size on its own line, the scale's ends below it.
                VStack(alignment: .leading, spacing: 2) {
                    chosenTitle
                    Text("Big strides to tiny steps")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: 440, alignment: .leading)
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement()
        .accessibilityLabel("Step size")
        .accessibilityValue(size.title)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(5, value + 1)
            case .decrement: value = max(1, value - 1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("toolkit.stepSize")
    }
}

/// Says where a Toolkit result came from.
struct ToolkitSourceLabel: View {
    let source: ToolkitSource
    var note: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(source.label, systemImage: source.symbol)
            if let note { Text(note) }
        }
        .font(.footnote).foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("toolkit.source")
    }
}

/// A calm placeholder while a suggestion is being made.
struct ToolkitThinking: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Today's focus from the energy check-in, if there is one.
extension JournalStore {
    var todaysFocus: FocusLevel? { journal.energy[todayKey].map { FocusLevel(energy: $0.value) } }
    var openPersonalTodos: [PersonalTodo] { PersonalTodo.ordered((journal.personalTodos ?? []).filter { !$0.completed }) }
}

// MARK: - Choosing a to-do

/// Lets a tool start from an open to-do, or from a new one typed here.
struct TodoChooser: View {
    @Environment(JournalStore.self) private var store
    let prompt: String
    let detail: (PersonalTodo) -> String?
    let choose: (PersonalTodo) -> Void
    @State private var newTitle = ""

    var body: some View {
        Panel(title: "New to-do") {
            HStack(spacing: 8) {
                TextField(prompt, text: $newTitle).glimmerField().onSubmit(add)
                    .accessibilityIdentifier("toolkit.newTodo")
                Button("Add", systemImage: "plus", action: add)
                    .glimmerButton(.standard).besideField()
                    .disabled(clean.isEmpty || clean.count > PersonalTodo.titleLimit)
                    .accessibilityIdentifier("toolkit.addTodo")
            }
        }
        Panel(title: "Your open to-dos", plain: true) {
            if store.openPersonalTodos.isEmpty {
                Text("No open to-dos yet. Add one above, or use Unload to empty your head first.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            VStack(spacing: 8) {
                ForEach(store.openPersonalTodos) { todo in
                    ActionRow(title: todo.title, detail: detail(todo), icon: Glyph.symbol(name: todo.title, category: "todo"), tint: Glyph.tint(for: "todo")) { choose(todo) }
                }
            }
            .glassGroup(spacing: 8)
        }
    }

    private var clean: String { newTitle.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func add() {
        guard !clean.isEmpty, clean.count <= PersonalTodo.titleLimit else { return }
        let todo = PersonalTodo(title: clean)
        if store.change({ $0.personalTodos = ($0.personalTodos ?? []) + [todo] }) {
            newTitle = ""
            choose(todo)
        }
    }
}

/// A roomy multi-line field for pasting or typing longer text. It sits straight on its panel's paper.
struct ToolkitTextEditor: View {
    @Binding var text: String
    let prompt: String
    var minHeight: CGFloat = 160

    // TextEditor insets its text a little; line the text up with the panel's headings instead.
    #if os(iOS)
    private static let inset = EdgeInsets(top: 8, leading: 5, bottom: 8, trailing: 5)
    #else
    private static let inset = EdgeInsets(top: 0, leading: 5, bottom: 0, trailing: 5)
    #endif

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, -Self.inset.leading)
            .frame(minHeight: minHeight)
            .background(alignment: .topLeading) {
                if text.isEmpty {
                    Text(prompt).foregroundStyle(.tertiary)
                        .padding(.top, Self.inset.top)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(prompt)
    }
}
