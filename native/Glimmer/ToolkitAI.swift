import Foundation
import FoundationModels

/// A Toolkit answer and where it came from.
struct ToolkitResult<Value> {
    let value: Value
    let source: ToolkitSource
    /// Set when a preferred route was unavailable, for example a disconnected writing agent.
    var note: String?
}

/// Routes each Toolkit request: the Mac's connected writing agent first, then Apple Intelligence
/// on this device, then Glimmer's offline guide. Text is only sent to an agent the person connected.
@MainActor
enum ToolkitAI {
    static var offlineOnly: Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        // UI tests stay deterministic unless a test asks for the model.
        return environment["GLIMMER_TEST_JOURNAL"] != nil && environment["GLIMMER_TEST_TOOLKIT_MODEL"] != "1"
        #else
        false
        #endif
    }

    static var hasDeviceModel: Bool {
        guard !offlineOnly else { return false }
        if #available(iOS 26, macOS 26, *) { return SystemLanguageModel.default.isAvailable }
        return false
    }

    /// The Coach agent the person chose on this Mac, when it can answer.
    static var agentChoice: CoachAgentChoice? {
        #if os(macOS)
        let choice = CoachAgentChoice.current
        guard !offlineOnly, choice.isReady else { return nil }
        return choice
        #else
        nil
        #endif
    }

    /// One line for the Toolkit page about where suggestions are made.
    static var routeSummary: String {
        if let agent = agentChoice {
            return hasDeviceModel
                ? "Suggestions come from \(agent.agent.title), or Apple Intelligence on this Mac when it’s unavailable."
                : "Suggestions come from \(agent.agent.title), or Glimmer’s offline guide when it’s unavailable."
        }
        return hasDeviceModel
            ? "Suggestions are made on this device with Apple Intelligence. Your words stay here."
            : "Apple Intelligence isn’t available here, so Glimmer’s offline guide makes simpler suggestions. Your words stay here."
    }

    static var canReadTone: Bool { agentChoice != nil || hasDeviceModel }

    // MARK: Tools

    static func breakDown(_ title: String, parent: String? = nil, size: StepSize) async -> ToolkitResult<[String]> {
        let input: [String: Any] = ["todo": title, "step": parent ?? NSNull(), "step_size": size.rawValue]
        var prompt = "To-do: \(title)\n"
        if let parent { prompt += "Break down only this one step of it: \(parent)\n" }
        prompt += size.guidance
        var note: String?
        if let payload = await agent(.breakItDown, input: input, prompt: prompt, note: &note),
           let reply = try? ToolkitReply.decode(ToolkitReply.Steps.self, from: payload) {
            let steps = ToolkitClean.lines(reply.steps)
            if !steps.isEmpty { return ToolkitResult(value: steps, source: .agent) }
        }
        if #available(iOS 26, macOS 26, *), hasDeviceModel,
           let generated = try? await session(.breakItDown).respond(to: prompt, generating: GeneratedSteps.self).content {
            let steps = ToolkitClean.lines(generated.steps)
            if !steps.isEmpty { return ToolkitResult(value: steps, source: .device, note: note) }
        }
        return ToolkitResult(value: OfflineToolkit.breakDown(parent ?? title, size: size, isStep: parent != nil),
                             source: .guide, note: note)
    }

    static func unload(_ text: String, today: Date) async -> ToolkitResult<[UnloadItem]> {
        let day = CalendarDay.key(today)
        let weekday = today.formatted(.dateTime.weekday(.wide))
        let input: [String: Any] = ["text": text, "today": day]
        let prompt = "Today is \(weekday), \(day).\nBrain dump:\n\(text)"
        var note: String?
        if let payload = await agent(.unload, input: input, prompt: prompt, note: &note),
           let reply = try? ToolkitReply.decode(ToolkitReply.Items.self, from: payload) {
            let items = clean(reply.items)
            if !items.isEmpty { return ToolkitResult(value: items, source: .agent) }
        }
        if #available(iOS 26, macOS 26, *), hasDeviceModel,
           let generated = try? await session(.unload).respond(to: prompt, generating: GeneratedUnload.self).content {
            // The small model is unreliable with calendar arithmetic, so Glimmer resolves the day words itself.
            let offline = OfflineToolkit.unload(text, today: today)
            let items = clean(generated.items.map { item in
                let named = OfflineToolkit.extractDue(item.when, today: today).1
                let matched = offline.first {
                    $0.title.localizedCaseInsensitiveContains(item.title) || item.title.localizedCaseInsensitiveContains($0.title)
                }?.dueDay
                return UnloadItem(title: item.title, dueDay: named ?? matched)
            })
            if !items.isEmpty { return ToolkitResult(value: items, source: .device, note: note) }
        }
        return ToolkitResult(value: OfflineToolkit.unload(text, today: today), source: .guide, note: note)
    }

    static func estimate(_ title: String, steps: [String], focus: FocusLevel) async -> ToolkitResult<Int> {
        let input: [String: Any] = ["todo": title, "steps": steps, "focus": focus.rawValue.lowercased()]
        var prompt = "To-do: \(title)\nFocus today: \(focus.rawValue) (\(focus.detail.lowercased()))."
        if !steps.isEmpty { prompt += "\nSteps:\n" + steps.map { "- " + $0 }.joined(separator: "\n") }
        var note: String?
        if let payload = await agent(.timeCheck, input: input, prompt: prompt, note: &note),
           let reply = try? ToolkitReply.decode(ToolkitReply.Minutes.self, from: payload), reply.minutes > 0 {
            return ToolkitResult(value: ToolkitClean.minutes(reply.minutes), source: .agent)
        }
        if #available(iOS 26, macOS 26, *), hasDeviceModel,
           let generated = try? await session(.timeCheck).respond(to: prompt, generating: GeneratedMinutes.self).content,
           generated.minutes > 0 {
            return ToolkitResult(value: ToolkitClean.minutes(generated.minutes), source: .device, note: note)
        }
        return ToolkitResult(value: OfflineToolkit.estimate(title, steps: steps.count, focus: focus), source: .guide, note: note)
    }

    /// Falls back to a rough word-pattern read when no model is available.
    static func readTheRoom(_ text: String, received: Bool) async -> ToolkitResult<ToneReading>? {
        let input: [String: Any] = ["text": text, "direction": received ? "received" : "sending"]
        let prompt = (received ? "A message the person received:\n" : "A message the person plans to send:\n") + text
        var note: String?
        if let payload = await agent(.readTheRoom, input: input, prompt: prompt, note: &note),
           let reply = try? ToolkitReply.decode(ToneReading.self, from: payload), !reply.tones.isEmpty {
            return ToolkitResult(value: clean(reply), source: .agent)
        }
        if #available(iOS 26, macOS 26, *), hasDeviceModel,
           let generated = try? await session(.readTheRoom).respond(to: prompt, generating: GeneratedReading.self).content {
            let reading = ToneReading(tones: generated.tones.map { ToneNote(tone: $0.tone, why: $0.why) }, takeaway: generated.takeaway)
            if !reading.tones.isEmpty { return ToolkitResult(value: clean(reading), source: .device, note: note) }
        }
        return OfflineToolkit.readTone(text, received: received).map { ToolkitResult(value: $0, source: .guide, note: note) }
    }

    /// Returns nil when the tone needs a model and none is available.
    static func reword(_ text: String, tone: RewordTone, size: StepSize) async -> ToolkitResult<String>? {
        let input: [String: Any] = ["text": text, "tone": tone.rawValue, "strength": size.rawValue]
        let prompt = "Tone: \(tone.rawValue). \(size.rewordStrength)\nMessage:\n\(text)"
        var note: String?
        if let payload = await agent(.reword, input: input, prompt: prompt, note: &note),
           let reply = try? ToolkitReply.decode(ToolkitReply.Text.self, from: payload), !reply.text.isEmpty {
            return ToolkitResult(value: String(reply.text.prefix(4_000)), source: .agent)
        }
        if #available(iOS 26, macOS 26, *), hasDeviceModel,
           let generated = try? await session(.reword).respond(to: prompt, generating: GeneratedText.self).content,
           !generated.text.isEmpty {
            return ToolkitResult(value: String(generated.text.prefix(4_000)), source: .device, note: note)
        }
        return OfflineToolkit.reword(text, tone: tone).map { ToolkitResult(value: $0, source: .guide, note: note) }
    }

    /// Returns nil without a model; the view then offers a blank pros and cons form.
    static func weigh(_ decision: String) async -> ToolkitResult<Weighing>? {
        let input: [String: Any] = ["decision": decision]
        let prompt = "Decision: \(decision)"
        var note: String?
        if let payload = await agent(.weighIt, input: input, prompt: prompt, note: &note),
           let reply = try? ToolkitReply.decode(Weighing.self, from: payload) {
            return ToolkitResult(value: clean(reply), source: .agent)
        }
        if #available(iOS 26, macOS 26, *), hasDeviceModel,
           let generated = try? await session(.weighIt).respond(to: prompt, generating: GeneratedWeighing.self).content {
            let weighing = Weighing(pros: generated.pros, cons: generated.cons, unknowns: generated.unknowns,
                                    experiment: generated.experiment)
            return ToolkitResult(value: clean(weighing), source: .device, note: note)
        }
        return nil
    }

    // MARK: Routes

    private static func agent(_ tool: ToolkitTool, input: [String: Any], prompt: String,
                              note: inout String?) async -> [String: Any]? {
        #if os(macOS)
        guard let choice = agentChoice else { return nil }
        do {
            return try await CoachAgentRoute.toolkit(choice, tool: tool, input: input, prompt: prompt)
        } catch is CancellationError {
            return nil
        } catch {
            note = "\(choice.agent.title) was unavailable."
            return nil
        }
        #else
        return nil
        #endif
    }

    @available(iOS 26, macOS 26, *)
    private static func session(_ tool: ToolkitTool) -> LanguageModelSession {
        LanguageModelSession(instructions: tool.instructions)
    }

    private static func clean(_ items: [UnloadItem]) -> [UnloadItem] {
        let titles = ToolkitClean.lines(items.map(\.title), limit: 30, length: PersonalTodo.titleLimit)
        return titles.map { line in
            let title = line.prefix(1).uppercased() + line.dropFirst()
            let due = items.first { $0.title.localizedCaseInsensitiveContains(line) }?.dueDay.flatMap { PracticeDate.parse($0) != nil ? $0 : nil }
            return UnloadItem(title: title, dueDay: due)
        }
    }

    private static func clean(_ reading: ToneReading) -> ToneReading {
        ToneReading(tones: reading.tones.prefix(4).map { ToneNote(tone: String($0.tone.prefix(40)), why: String($0.why.prefix(300))) },
                    takeaway: String(reading.takeaway.prefix(500)))
    }

    private static func clean(_ weighing: Weighing) -> Weighing {
        Weighing(pros: ToolkitClean.lines(weighing.pros, limit: 6, length: 200),
                 cons: ToolkitClean.lines(weighing.cons, limit: 6, length: 200),
                 unknowns: ToolkitClean.lines(weighing.unknowns, limit: 5, length: 200),
                 experiment: String(weighing.experiment.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)))
    }
}

// MARK: - Guided generation

@available(iOS 26, macOS 26, *)
@Generable
private struct GeneratedSteps {
    @Guide(description: "Concrete steps in order. Each starts with a verb and is under 12 words.", .maximumCount(12))
    let steps: [String]
}

@available(iOS 26, macOS 26, *)
@Generable
private struct GeneratedUnloadItem {
    @Guide(description: "One actionable to-do that starts with a verb, under 12 words, without the day.")
    let title: String
    @Guide(description: "The exact day words the text uses for this item, such as tomorrow or by Friday, otherwise an empty string.")
    let when: String
}

@available(iOS 26, macOS 26, *)
@Generable
private struct GeneratedUnload {
    @Guide(description: "Every separate action in the brain dump, in the order written.", .maximumCount(30))
    let items: [GeneratedUnloadItem]
}

@available(iOS 26, macOS 26, *)
@Generable
private struct GeneratedMinutes {
    @Guide(description: "Realistic whole minutes for this person today.", .range(1...600))
    let minutes: Int
}

@available(iOS 26, macOS 26, *)
@Generable
private struct GeneratedTone {
    @Guide(description: "One or two words, for example Warm, Rushed or Firm.")
    let tone: String
    @Guide(description: "A short, plain reason that points to the words causing it.")
    let why: String
}

@available(iOS 26, macOS 26, *)
@Generable
private struct GeneratedReading {
    @Guide(description: "Two to four tones the message may carry.", .count(2...4))
    let tones: [GeneratedTone]
    @Guide(description: "One or two sentences on what a neutral reader would take away.")
    let takeaway: String
}

@available(iOS 26, macOS 26, *)
@Generable
private struct GeneratedText {
    @Guide(description: "The rewritten message only.")
    let text: String
}

@available(iOS 26, macOS 26, *)
@Generable
private struct GeneratedWeighing {
    @Guide(description: "Short reasons for it.", .maximumCount(5))
    let pros: [String]
    @Guide(description: "Short reasons against it.", .maximumCount(5))
    let cons: [String]
    @Guide(description: "What the person doesn't know yet.", .maximumCount(4))
    let unknowns: [String]
    @Guide(description: "One small, reversible 7-day experiment, written as an action.")
    let experiment: String
}
