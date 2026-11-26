import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Read the room: how a message might come across, before you reply or send.
struct ReadTheRoomView: View {
    @SceneStorage("glimmer.toolkit.room") private var text = ""
    @State private var received = true
    @State private var reading: ToolkitResult<ToneReading>?
    @State private var working: Task<Void, Never>?
    @State private var readText = ""

    var body: some View {
        Page(title: "Read the room", subtitle: "Paste a message to see how it might come across. Nothing leaves your device unless you’ve connected a writing agent.", width: 620) {
            GlassSegments(label: "Whose message is it?",
                          options: [GlassSegment(value: true, title: "I received it"),
                                    GlassSegment(value: false, title: "I’m sending it")],
                          selection: $received)
                .accessibilityIdentifier("room.direction")
            Panel {
                ToolkitTextEditor(text: $text, prompt: received ? "Paste the message you got…" : "Paste what you plan to send…")
                    .accessibilityIdentifier("room.text")
            }
            if working != nil { Panel { ToolkitThinking(text: "Reading it through…") } }
            if let reading { result(reading) }
        }
        .actionBar(width: 620) {
            if reading == nil {
                PrimaryAction(title: "Read the room", systemImage: "eye", action: read)
                    .disabled(working != nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("room.read")
            }
        }
        .onChange(of: received) { reading = nil }
        .onChange(of: text) { if reading != nil && text != readText { reading = nil } }
        .onDisappear { working?.cancel() }
        #if DEBUG
        .onAppear {
            guard text.isEmpty, let sample = ToolkitSample.text else { return }
            text = sample
            ToolkitSample.run { read() }
        }
        #endif
    }

    @ViewBuilder private func result(_ reading: ToolkitResult<ToneReading>) -> some View {
        Panel(title: "How it may come across") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(reading.value.tones) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.tone).font(.headline)
                        Text(note.why.prefix(1).uppercased() + note.why.dropFirst()).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("room.tones")
            Divider()
            Text(reading.value.takeaway).fixedSize(horizontal: false, vertical: true)
            ToolkitSourceLabel(source: reading.source, note: reading.note)
            if !received {
                NavigationLink { RewordView(initial: text) } label: {
                    Label("Reword it", systemImage: "wand.and.sparkles").fontWeight(.medium).frame(minHeight: 24)
                }
                .glimmerButton().buttonBorderShape(.capsule).controlSize(.large)
                .accessibilityIdentifier("room.reword")
            }
        }
    }

    private func read() {
        let message = text
        let direction = received
        readText = message
        working = Task {
            let result = await ToolkitAI.readTheRoom(message, received: direction)
            if !Task.isCancelled { reading = result }
            working = nil
        }
    }
}

/// Reword: the same message in a different tone.
struct RewordView: View {
    @AppStorage(StepSize.preference) private var stepSize = StepSize.balanced.rawValue
    @Environment(\.readingTheme) private var theme
    @State private var text: String
    @State private var tone: RewordTone
    @State private var rewrite: ToolkitResult<String>?
    @State private var previous: String?
    @State private var working: Task<Void, Never>?
    @State private var copied = false
    private let hasModel = ToolkitAI.canReadTone
    /// Without a model, the tones that still work come first so they're in view.
    private var tones: [RewordTone] {
        hasModel ? RewordTone.allCases : RewordTone.allCases.filter(\.worksOffline) + RewordTone.allCases.filter { !$0.worksOffline }
    }

    init(initial: String = "") {
        _text = State(initialValue: initial)
        _tone = State(initialValue: ToolkitAI.canReadTone ? .kinder : .shorter)
    }

    var body: some View {
        Page(title: "Reword", subtitle: "Say the same thing in a different tone. Your meaning, names and facts stay put.", width: 620) {
            Panel {
                ToolkitTextEditor(text: $text, prompt: "Paste or type your message…", minHeight: rewrite == nil ? 160 : 72)
                    .accessibilityIdentifier("reword.text")
                if previous != nil {
                    Button("Undo", systemImage: "arrow.uturn.backward") {
                        if let previous { text = previous }
                        previous = nil
                    }
                    .font(.callout).buttonStyle(.borderless)
                }
            }
            if working != nil { Panel { ToolkitThinking(text: "Rewording…") } }
            if let rewrite { result(rewrite) }
            Panel(title: "Tone") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tones) { option in
                            Chip(label: option.rawValue, selected: tone == option, tint: theme.selectionInk) { tone = option }
                                .disabled(!hasModel && !option.worksOffline)
                                .opacity(!hasModel && !option.worksOffline ? 0.4 : 1)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
                .accessibilityIdentifier("reword.tone")
                Text(hasModel
                     ? "Step size sets how much it changes: \(StepSize(rawValue: stepSize)?.title.lowercased() ?? "balanced")."
                     : "Without Apple Intelligence or a connected writing agent, Glimmer can make it shorter or turn it into bullet points.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .actionBar(width: 620) {
            if let rewrite {
                Button("Try again", systemImage: "arrow.clockwise", action: run)
                    .glimmerButton().controlSize(.large)
                    .disabled(working != nil)
                    .accessibilityIdentifier("reword.run")
                PrimaryAction(title: copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") { copy(rewrite.value) }
                    .accessibilityIdentifier("reword.copy")
            } else {
                PrimaryAction(title: "Reword", systemImage: "wand.and.sparkles", action: run)
                    .disabled(working != nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || (!hasModel && !tone.worksOffline))
                    .accessibilityIdentifier("reword.run")
            }
        }
        .hidesTabBar()
        .onChange(of: tone) { rewrite = nil }

        .onDisappear { working?.cancel() }
        #if DEBUG
        .onAppear {
            guard text.isEmpty, let sample = ToolkitSample.text else { return }
            text = sample
            ToolkitSample.run { run() }
        }
        #endif
    }

    @ViewBuilder private func result(_ rewrite: ToolkitResult<String>) -> some View {
        Panel(title: tone.rawValue) {
            Text(rewrite.value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reword.result")
            ToolkitSourceLabel(source: rewrite.source, note: rewrite.note)
            FlowLayout(spacing: 8) {
                Button("Use this", systemImage: "arrow.up.doc") {
                    previous = text
                    text = rewrite.value
                    self.rewrite = nil
                }
                .accessibilityHint("Replaces your message so you can reword it again")
                ShareLink(item: rewrite.value)
            }
            .glimmerButton()
        }
    }

    private func run() {
        let message = text
        let chosen = tone
        let size = StepSize(rawValue: stepSize) ?? .balanced
        copied = false
        working = Task {
            let result = await ToolkitAI.reword(message, tone: chosen, size: size)
            if !Task.isCancelled { rewrite = result }
            working = nil
        }
    }

    private func copy(_ value: String) {
        #if os(iOS)
        UIPasteboard.general.string = value
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
        copied = true
    }
}

#if DEBUG
/// Review launches: GLIMMER_TOOLKIT_TEXT fills a Toolkit field ("|" is a new line).
enum ToolkitSample {
    static var text: String? {
        ProcessInfo.processInfo.environment["GLIMMER_TOOLKIT_TEXT"]?.replacingOccurrences(of: "|", with: "\n")
    }
    /// Runs the tool once the page has settled, when GLIMMER_TOOLKIT_AUTORUN=1.
    @MainActor static func run(_ action: @escaping @MainActor () -> Void) {
        guard ProcessInfo.processInfo.environment["GLIMMER_TOOLKIT_AUTORUN"] == "1" else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            action()
        }
    }
}
#endif
