import SwiftUI

/// Weigh it: pros, cons and unknowns for a decision, ending in a small 7-day experiment.
struct WeighItView: View {
    @Environment(JournalStore.self) private var store
    @SceneStorage("glimmer.toolkit.weigh") private var decision = ""
    @State private var weighing: Weighing?
    @State private var source: (source: ToolkitSource, note: String?)?
    @State private var working: Task<Void, Never>?
    @State private var weighed = ""

    private var cleanDecision: String { decision.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Page(title: "Weigh it", subtitle: "Lay a decision out where you can see it. Glimmer won’t decide for you.", width: 620) {
            Panel(title: "What are you deciding?") {
                ToolkitTextEditor(text: $decision, prompt: "Should I…", minHeight: 76)
                    .accessibilityIdentifier("weigh.decision")
            }
            if working != nil { Panel { ToolkitThinking(text: "Weighing it up…") } }
            if weighing != nil { result }
        }
        .actionBar(width: 620) {
            if weighing == nil {
                PrimaryAction(title: "Weigh it", systemImage: "scalemass", action: weigh)
                    .disabled(working != nil || cleanDecision.isEmpty)
                    .accessibilityIdentifier("weigh.run")
            } else {
                Button("Start over", systemImage: "arrow.uturn.backward") {
                    weighing = nil
                    source = nil
                }
                .glimmerButton().controlSize(.large)
                PrimaryAction(title: "Try it for 7 days", systemImage: "calendar", action: startExperiment)
                    .disabled((weighing?.experiment ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("weigh.experiment")
            }
        }
        .onChange(of: decision) {
            if weighing != nil && cleanDecision != weighed { weighing = nil; source = nil }
        }
        .onDisappear { working?.cancel() }
        #if DEBUG
        .onAppear {
            guard decision.isEmpty, let sample = ToolkitSample.text else { return }
            decision = sample
            ToolkitSample.run { weigh() }
        }
        #endif
    }

    @ViewBuilder private var result: some View {
        if let binding = Binding($weighing) {
            WeighList(title: "For", symbol: "plus", items: binding.pros)
            WeighList(title: "Against", symbol: "minus", items: binding.cons)
            WeighList(title: "Still unknown", symbol: "questionmark", items: binding.unknowns)
            Panel(title: "A small experiment") {
                ToolkitTextEditor(text: binding.experiment, prompt: "Something small you could try for a week", minHeight: 76)
                    .accessibilityIdentifier("weigh.experimentText")
                Text("Seven days of a small, reversible version often tells you more than thinking it over.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let source { ToolkitSourceLabel(source: source.source, note: source.note) }
            }
        }
    }

    private func weigh() {
        let question = cleanDecision
        guard !question.isEmpty, working == nil else { return }
        weighed = question
        working = Task {
            let result = await ToolkitAI.weigh(question)
            guard !Task.isCancelled else { return }
            if let result {
                weighing = result.value.sentenceCased
                source = (result.source, result.note)
            } else {
                weighing = OfflineToolkit.weighing(question)
                source = (.guide, "Add your own reasons below. Apple Intelligence or a connected writing agent can suggest some.")
            }
            working = nil
        }
    }

    private func startExperiment() {
        guard let experiment = weighing?.experiment.trimmingCharacters(in: .whitespacesAndNewlines), !experiment.isEmpty else { return }
        let title = String(experiment.prefix(140))
        store.startOrQueue(Suggestion(type: "Decision", title: title, sub: String(cleanDecision.prefix(160))))
    }
}

/// An editable list of reasons. People can add their own or remove suggested ones.
private struct WeighList: View {
    let title: String
    let symbol: String
    @Binding var items: [String]
    @State private var draft = ""
    @State private var adding = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Panel(title: title) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: symbol).font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            .frame(width: 14).accessibilityHidden(true)
                        Text(item).frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Remove", systemImage: "xmark") { items.remove(at: index) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                            .accessibilityLabel("Remove \(item)")
                    }
                }
            }
            if adding {
                HStack(spacing: 8) {
                    TextField("Add your own", text: $draft).glimmerField().focused($fieldFocused).onSubmit(add)
                    Button("Add", systemImage: "plus", action: add)
                        .glimmerButton(.standard).besideField()
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Add to \(title)")
                }
            } else if items.count < 12 {
                Button {
                    adding = true
                    fieldFocused = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus").font(.footnote.weight(.semibold)).frame(width: 14)
                        Text(items.isEmpty ? "Add a reason" : "Add your own")
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).contentShape(.rect)
                }
                .buttonStyle(RowPressStyle())
                .accessibilityLabel("Add your own to \(title)")
            }
        }
    }

    private func add() {
        let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, items.count < 12 else { return }
        items.append(String(clean.prefix(160)))
        draft = ""
        adding = false
    }
}
