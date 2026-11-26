import FoundationModels
import SwiftUI

#if os(macOS)
/// Settings → Coach: who answers in Coach and the Toolkit, with model, effort and time limit,
/// following Inkspring's writing agent and OpenTalon's task agent settings.
struct CoachAgentSettings: View {
    @AppStorage(CoachAgent.preference) private var savedAgent = ""
    @AppStorage(CoachAgentChoice.timeoutKey) private var savedTimeout = 90
    @State private var revision = 0
    @State private var customModel = ""
    @State private var testing: Task<Void, Never>?
    @State private var testResult: String?
    @State private var testFailed = false

    private var choice: CoachAgentChoice {
        _ = (savedAgent, savedTimeout, revision)
        return CoachAgentChoice.current
    }

    var body: some View {
        let choice = choice
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose who answers in Coach and the Toolkit. Local agents use the account you signed in to on this Mac.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                ForEach(CoachAgent.allCases) { agent in
                    let selected = agent == choice.agent
                    Button { select(agent) } label: {
                        RowLabel(title: agent.title, detail: detail(agent), icon: agent.symbol, tint: GlimmerColor.ember,
                                 trailing: selected ? "checkmark" : nil, selected: selected)
                    }
                    .glassRow(tint: GlimmerColor.ember, selected: selected)
                    .accessibilityIdentifier("coach.agent.\(agent.rawValue)")
                }
            }
            .glassGroup(spacing: 6)

            if choice.agent.isLocalAgent {
                agentOptions(choice)
            } else if choice.agent == .server {
                CoachServerFields()
            } else {
                Text(CoachDeviceRoute.summary)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if choice.agent != .device {
                Divider()
                HStack(spacing: 10) {
                    Button(testing == nil ? "Test Coach" : "Testing…", systemImage: "checkmark.circle") { test(choice) }
                        .glimmerButton()
                        .disabled(testing != nil || !choice.isReady)
                        .accessibilityIdentifier("coach.test")
                    if testing != nil { ProgressView().controlSize(.small).accessibilityLabel("Testing Coach") }
                }
                if let testResult {
                    Label(testResult, systemImage: testFailed ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(testFailed ? GlimmerColor.ember : GlimmerColor.sage)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("coach.testResult")
                }
            }
        }
        .onChange(of: choice.agent) { _, _ in
            testResult = nil
            customModel = ""
        }
        .onDisappear { testing?.cancel() }
        #if DEBUG
        .task {
            let environment = ProcessInfo.processInfo.environment
            if environment["GLIMMER_TEST_JOURNAL"] != nil, environment["GLIMMER_COACH_TEST"] == "1" { test(choice) }
        }
        #endif
    }

    @ViewBuilder private func agentOptions(_ choice: CoachAgentChoice) -> some View {
        let agent = choice.agent
        if agent.executable == nil, let guide = agent.guide {
            Link(destination: guide) {
                RowLabel(title: "Install \(agent.title)", detail: "Then sign in once in Terminal", icon: "arrow.down.circle.fill",
                         tint: GlimmerColor.ember, trailing: "arrow.up.right")
            }
            .glassRow(tint: GlimmerColor.ember)
        }
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Model")
            FlowLayout(spacing: 8) {
                let options = (agent == .gemini ? [] : [""]) + agent.models.map(\.id)
                let current = choice.model.isEmpty ? (agent.defaultModel ?? "") : choice.model
                ForEach(options, id: \.self) { id in
                    Button {
                        save(id, key: CoachAgentChoice.modelKey(agent))
                    } label: {
                        HStack(spacing: 6) {
                            Text(agent.modelName(id))
                            if current == id { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                    }
                    .glimmerButton(current == id ? .selected : .standard)
                    .accessibilityAddTraits(current == id ? .isSelected : [])
                }
                if !options.contains(current) {
                    Button { } label: {
                        HStack(spacing: 6) { Text(current); Image(systemName: "checkmark").accessibilityHidden(true) }
                    }
                    .glimmerButton(.selected)
                    .accessibilityAddTraits(.isSelected)
                }
            }
            .accessibilityIdentifier("coach.model")
            if agent != .gemini {
                HStack(spacing: 8) {
                    TextField("Custom model ID", text: $customModel).glimmerField()
                        .onSubmit { useCustomModel(agent) }
                    Button("Use model") { useCustomModel(agent) }
                        .glimmerButton().besideField()
                        .disabled(customModel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Reasoning effort")
            let efforts = (agent == .gemini ? [] : [""]) + agent.efforts(model: choice.model.isEmpty ? agent.defaultModel : choice.model)
            let effort = efforts.contains(choice.effort) ? choice.effort : (agent == .gemini ? "high" : "")
            GlassSegments(label: "Reasoning effort",
                          options: efforts.map { GlassSegment(value: $0, title: CoachAgent.effortName($0)) },
                          selection: Binding(get: { effort }, set: { save($0, key: CoachAgentChoice.effortKey(agent)) }))
                .accessibilityIdentifier("coach.effort")
        }
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Time limit")
            GlassSegments(label: "Time limit",
                          options: CoachAgentChoice.timeouts.map { GlassSegment(value: $0, title: $0 < 120 ? "\($0) s" : "2 min") },
                          selection: Binding(get: { choice.timeout }, set: { savedTimeout = $0 }))
                .frame(maxWidth: 360)
        }
        Text("Coach sends \(agent.title) your question, your recent Coach messages and the practices it can suggest. Your journal stays on this device. \(agent == .gemini ? "Gemini runs through Google’s Antigravity CLI (agy) with your Google sign-in." : "Agent default uses the model set in \(agent.title).")")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func detail(_ agent: CoachAgent) -> String {
        switch agent {
        case .device: CoachDeviceRoute.title
        case .server:
            CoachMCP.url(UserDefaults.standard.string(forKey: CoachMCP.preference) ?? "") == nil ? "Not connected" : "Connected"
        default:
            agent.executable.map(Self.location) ?? "Not installed on this Mac"
        }
    }

    /// "~/.local/bin/claude", or "Installed with ChatGPT" for a tool inside an app.
    static func location(_ url: URL) -> String {
        if let app = url.pathComponents.first(where: { $0.hasSuffix(".app") }) {
            return "Installed with " + app.dropLast(4)
        }
        return url.path.replacingOccurrences(of: CoachAgentRunner.userHome, with: "~")
    }

    private func select(_ agent: CoachAgent) {
        savedAgent = agent.rawValue
        revision += 1
    }

    private func save(_ value: String, key: String) {
        UserDefaults.standard.set(value, forKey: key)
        revision += 1
        testResult = nil
    }

    private func useCustomModel(_ agent: CoachAgent) {
        let id = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        save(String(id.prefix(120)), key: CoachAgentChoice.modelKey(agent))
        customModel = ""
    }

    private func test(_ choice: CoachAgentChoice) {
        testResult = nil
        testing = Task {
            defer { testing = nil }
            do {
                testResult = try await CoachAgentRoute.test(choice)
                testFailed = false
            } catch is CancellationError {
            } catch {
                testResult = error.localizedDescription
                testFailed = true
            }
            revision += 1
        }
    }
}

/// A sheet version of the Coach settings, opened from the Coach composer.
struct CoachAgentSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Coach replies").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                CoachAgentSettings()
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.glimmerButton(.prominent).keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .background { PageBackdrop() }
        #if os(macOS)
        .frame(width: 560, height: 640)
        #endif
    }
}

#endif

/// How Coach answers without an agent.
enum CoachDeviceRoute {
    static var hasAppleModel: Bool {
        if #available(iOS 26, macOS 26, *) { return SystemLanguageModel.default.isAvailable }
        return false
    }

    static var title: String { hasAppleModel ? "Apple Intelligence" : "Glimmer’s practice guide" }

    static var summary: String {
        hasAppleModel
            ? "Coach answers with Apple Intelligence on this device. Your words and journal stay here."
            : "Apple Intelligence isn’t available here, so Coach suggests practices from Glimmer’s guide."
    }
}

/// Settings → Coach diagnostics: what answered last and why it failed, for support. Never questions or replies.
struct CoachDiagnosticsPanel: View {
    @AppStorage(CoachAgent.preference) private var savedAgent = ""

    var body: some View {
        let choice = CoachAgentChoice.current
        Panel(title: "Coach diagnostics") {
            VStack(spacing: 6) {
                SettingsValueRow(label: "Replies with", value: choice.agent == .device ? CoachDeviceRoute.title : choice.title)
                #if os(macOS)
                if choice.agent.isLocalAgent {
                    SettingsValueRow(label: "Command line tool", value: choice.agent.executable?.path ?? "Not found")
                    SettingsValueRow(label: "Reasoning effort", value: CoachAgent.effortName(choice.effort.isEmpty && choice.agent == .gemini ? "high" : choice.effort))
                }
                #endif
                SettingsValueRow(label: "Last agent reply", value: SyncTimestamp.text(CoachAgentLog.lastSuccess))
                if let detail = CoachAgentLog.lastFailureDetail {
                    SettingsValueRow(label: "Last error", value: SyncTimestamp.text(CoachAgentLog.lastFailure))
                    Text(detail).font(.callout).foregroundStyle(GlimmerColor.ember)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("coach.lastError")
                }
            }
            .font(.callout)
            ShareLink(item: report(choice)) {
                RowLabel(title: "Share Coach Diagnostics", icon: "square.and.arrow.up", trailing: nil)
            }
            .glassRow()
            .accessibilityIdentifier("settings.shareCoachDiagnostics")
            Text("Includes the agent, model, tool location and recent errors. Your questions, Coach replies and journal are not included.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(savedAgent)
    }

    private func report(_ choice: CoachAgentChoice) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        var lines = ["Glimmer \(version) (\(build))", "Coach: \(choice.agent.title)",
                     "Apple Intelligence: \(CoachDeviceRoute.hasAppleModel ? "available" : "unavailable")"]
        #if os(macOS)
        if choice.agent.isLocalAgent {
            lines += ["Model: \(choice.resolvedModel ?? "agent default")", "Effort: \(choice.resolvedEffort ?? "default")",
                      "Time limit: \(choice.timeout) s", "Tool: \(choice.agent.executable?.path ?? "not found")"]
        }
        #endif
        lines.append("Last agent reply: \(SyncTimestamp.text(CoachAgentLog.lastSuccess))")
        if let detail = CoachAgentLog.lastSuccessDetail { lines.append(detail) }
        if let detail = CoachAgentLog.lastFailureDetail {
            lines.append("Last error: \(SyncTimestamp.text(CoachAgentLog.lastFailure))")
            lines.append(detail)
        }
        return lines.joined(separator: "\n")
    }
}
