import SwiftUI

struct OnboardingView: View {
    @Environment(JournalStore.self) private var store
    let catalog: Catalog
    var onFinishReplay: (() -> Void)?
    @State private var replayIndex = 0
    @State private var replayAnswers: [String: [String]] = [:]
    @State private var name = ""
    @State private var forward = true
    private var replaying: Bool { onFinishReplay != nil }
    private var index: Int {
        min(max(0, replaying ? replayIndex : store.journal.onboardingIndex), catalog.onboarding.count - 1)
    }
    private var answers: [String: [String]] { replaying ? replayAnswers : store.journal.answers }
    private var step: OnboardingStep { catalog.onboarding[index] }
    private var isLast: Bool { index == catalog.onboarding.count - 1 }
    private var choices: [String] { answers[step.key ?? "", default: []] }

    var body: some View {
        VStack(spacing: 0) {
            header
            Page(title: heading, kicker: step.kicker ?? "Welcome to Glimmer", subtitle: step.sub ?? hint, width: 640) {
                content
                    .modifier(ReadingPageTurn(forward: forward))
            }
            .id(index)
        }
        .actionBar(width: 640) {
            if let onFinishReplay {
                SecondaryAction(title: "Skip onboarding", systemImage: "xmark", fill: false, action: onFinishReplay)
                    .accessibilityIdentifier("onboardingSkip")
            }
            if index > 0 {
                SecondaryAction(title: "Back", systemImage: "chevron.left", fill: false) {
                    forward = false
                    go(to: max(0, index - 1))
                }
                .accessibilityIdentifier("onboardingBack")
                .keyboardShortcut(.leftArrow, modifiers: .command)
            }
            PrimaryAction(title: isLast ? (replaying ? "Done" : "Start my plan") : "Continue", systemImage: isLast ? "sparkles" : nil) {
                if isLast {
                    if let onFinishReplay { onFinishReplay() }
                    else { store.start(name: name) }
                } else {
                    forward = true
                    go(to: index + 1)
                }
            }
            .disabled(step.key != nil && choices.isEmpty)
            .accessibilityIdentifier("onboardingContinue")
            .keyboardShortcut(.defaultAction)
        }
        .background { PageBackdrop() }
        .onAppear { if !replaying { name = store.journal.name } }
    }

    private func go(to value: Int) {
        if replaying { replayIndex = value }
        else { store.change { $0.onboardingIndex = value } }
    }

    private func setAnswer(_ choice: [String], for key: String) {
        if replaying { replayAnswers[key] = choice }
        else { store.change { $0.answers[key] = choice } }
    }

    private var header: some View {
        HStack(spacing: 14) {
            StepDots(current: index, total: catalog.onboarding.count)
            Text("\(index + 1) of \(catalog.onboarding.count)").font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .frame(maxWidth: 640, minHeight: 44)
        .padding(.horizontal, 20).padding(.top, 10)
        .frame(maxWidth: .infinity)
    }

    private var hint: String? {
        guard step.kind == "q" else { return nil }
        if step.mode == "single" { return "Choose one." }
        return step.max.map { "Choose up to \($0)." } ?? "Choose all that apply."
    }

    private var heading: String {
        if let title = step.title { return title }
        return switch step.kind {
        case "welcome": "A quiet place to get unstuck"
        case "note": "Notice the aftertaste"
        case "exp": "Pick one small thing to try"
        case "profile": "What you want to work on"
        case "projection": "What to try on a hard day"
        default: "Your plan is ready"
        }
    }

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 270), spacing: 10)] }

    @ViewBuilder private var content: some View {
        switch step.kind {
        case "welcome":
            ZStack(alignment: .bottomLeading) {
                Artwork(slot: 0, height: 148)
                GlimmerLogo(size: 48)
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    .padding(12)
                    .readingArrival(delay: 0.18)
            }
            .readingArrival()
            Panel(padding: 22) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Glimmer is a gentle spiritual life coach for minds too busy thinking. Take a quiet moment to consider what matters in your work, your rest, and the way you treat people.")
                            .font(GlimmerFont.display(.title3))
                        Text("Start by recalling one moment you liked or that drained you, and jot it down if you want. Your journal is just a quiet place to keep what stands out, and experiments are small things you can try.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Panel(title: "What should I call you?") {
                TextField("First name (optional)", text: $name)
                    .glimmerField()
                    .onChange(of: name) { _, value in
                        if !replaying { store.change { $0.name = value } }
                    }
                Label("Your journal is saved on this device. No Glimmer account required.", systemImage: "lock")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if store.canUseCloud && !replaying { CloudSyncPanel() }
        case "q":
            if let key = step.key {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(step.options ?? []) { option in
                        OnboardingChoice(label: option.label, selected: choices.contains(option.v), multiple: step.mode == "multi") {
                            setAnswer(step.toggling(option.v, in: answers[key, default: []]), for: key)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        case "note":
            Panel(padding: 22) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "dial.medium").font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(GlimmerColor.accent).frame(width: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Aftertaste is how you feel after the thing you just did.")
                            .font(GlimmerFont.display(.title3, weight: .bold))
                        Text("It can be different from how much you wanted to do it. A quick log helps you spot the difference.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case "exp":
            Text("Built from what you just told me. Small, reversible, your call.").foregroundStyle(.secondary)
            VStack(spacing: 10) {
                ForEach(catalog.startingSuggestions(answers)) { suggestion in
                    SelectRow(label: suggestion.title,
                              selected: answers["first_experiment"]?.first == suggestion.id) {
                        setAnswer([suggestion.id], for: "first_experiment")
                    }
                }
            }
            .glassGroup(spacing: 10)
        case "profile":
            Panel {
                ForEach(["primary_goal", "distraction", "aftertaste", "wants", "coach_style"], id: \.self) { key in
                    if let question = catalog.onboarding.first(where: { $0.key == key }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Eyebrow(question.kicker ?? "")
                            Text((question.options ?? []).filter { answers[key, default: []].contains($0.v) }
                                .map(\.label).joined(separator: " · "))
                                .font(.body.weight(.medium))
                        }
                        if key != "coach_style" { Divider() }
                    }
                }
            }
        case "projection":
            VStack(spacing: 12) {
                tip("arrow.down.right.circle", "Make the first step smaller",
                    "If a task feels too big, start by opening the document or putting one cup in the sink.")
                tip("timer", "Make time visible", "Try a short timer before an activity that tends to run long.")
                tip("dial.medium", "Check in afterward",
                    "Use the aftertaste dial to notice how you feel. Over time, your logs can show which changes are worth keeping.")
            }
        default:
            Panel(padding: 22) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow("Your first experiment", color: GlimmerColor.ember)
                        if let first = answers["first_experiment"]?.first {
                            Text(first).font(GlimmerFont.display(.title2, weight: .bold))
                        }
                        Text("Start with one small log. The coach learns from what you choose to notice.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func tip(_ icon: String, _ title: String, _ text: String) -> some View {
        Panel {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon).font(.title2).foregroundStyle(GlimmerColor.accent).frame(width: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct OnboardingChoice: View {
    let label: String
    let selected: Bool
    let multiple: Bool
    let action: () -> Void
    @Environment(\.readingTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let outline = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: action) {
            HStack(spacing: 14) {
                Text(label)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                let mark = RoundedRectangle(cornerRadius: multiple ? 6 : 12, style: .continuous)
                ZStack {
                    mark.fill(selected ? GlimmerColor.accent : .clear)
                    mark.strokeBorder(selected ? .clear : Color.secondary.opacity(0.55), lineWidth: 1.5)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(theme.surface)
                        .opacity(selected ? 1 : 0)
                        .animation(reduceMotion || selected ? nil : .easeOut(duration: 0.14), value: selected)
                }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(theme.surface, in: outline)
            .overlay {
                outline.fill(GlimmerColor.accent.opacity(selected ? 0.08 : 0))
                    .allowsHitTesting(false)
            }
            .overlay {
                outline.strokeBorder(selected ? GlimmerColor.accent.opacity(0.40) : Color.primary.opacity(0.13))
            }
            .completionLight(selected, outline: outline)
            .contentShape(outline)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
