#if os(macOS)
import SwiftUI

enum AgentGuideStep: Int, CaseIterable {
    case access, connect, verify
    var title: String {
        switch self {
        case .access: "Choose what to share"
        case .connect: "Connect your agent"
        case .verify: "Try your first question"
        }
    }
}

struct AgentTutorial: View {
    @Environment(\.dismiss) private var dismiss
    @State var step: AgentGuideStep = .access
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Agent setup").font(.headline); Spacer(); Button("Close") { dismiss() }.keyboardShortcut(.cancelAction).glimmerButton() }
            StepDots(current: step.rawValue, total: AgentGuideStep.allCases.count)
            Text(step.title).font(GlimmerFont.reading(.title, weight: .medium))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if step == .access {
                        Text("MCP connects an assistant on this Mac to Glimmer. Ask for today’s reflection or a practice to add to your daily dashboard.")
                    } else if step == .connect {
                        Text("Choose the app where you want to ask Glimmer a question.")
                    } else {
                        Text("Test the local connector here. Then open your assistant and ask:")
                        Text("“What’s my daily Glimmer, and what’s one practice I can try today?”")
                            .font(GlimmerFont.reading(.title3)).textSelection(.enabled)
                    }
                    AgentSetupContent(section: step).id(step)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if step != .access {
                    Button("Back") { step = AgentGuideStep(rawValue: step.rawValue - 1) ?? .access }.glimmerButton()
                }
                Spacer()
                Button(step == .verify ? "Done" : "Continue") {
                    if let next = AgentGuideStep(rawValue: step.rawValue + 1) { step = next } else { dismiss() }
                }.keyboardShortcut(.defaultAction).glimmerButton(.prominent)
            }
        }.padding(24).frame(width: 520, height: 470).background { PageBackdrop() }
    }
}

struct AgentSetupContent: View {
    let section: AgentGuideStep
    @Environment(JournalStore.self) private var store
    @Environment(\.readingTheme) private var theme
    @State private var agentError = false
    @State private var agentClient = "Claude Code"
    @State private var agentMessage: String?
    @State private var testingAgent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch section {
            case .access:
                agentToggle("Share read-only summaries", detail: "Daily coaching, the practice catalog, grouped ratings and plan counts",
                            isOn: store.agentLevel != .off) { $0 ? .summaries : .off }
                agentToggle("Let agents log and check off", detail: "Save practices, check off tasks, log moments and record energy",
                            isOn: store.agentLevel == .changes) { $0 ? .changes : .summaries }
                    .disabled(store.agentLevel == .off)
                Text(store.agentLevel == .changes
                     ? "Connected agents can read today’s plan with task names and add to your journal. They may send what they read to their model provider."
                     : "Connected agents can read today’s coaching, its saved/completed state, public exercises and summary counts. They may send the results to their model provider. You can turn access off here at any time.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if store.agentLevel == .summaries {
                    Label("Never shared: journal entries, custom source names, task titles or onboarding answers.", systemImage: "eye.slash")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if store.agentLevel != .off {
                    Text("For a daily dashboard, ask your agent to fetch the Daily Glimmer on your schedule. Enable check-offs if you want it to save a practice and record completion when you report it.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if agentError {
                    Label("Couldn’t change agent access. Please try again.", systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(GlimmerColor.ember)
                }

            case .connect:
                GlassSegments(label: "Client", options: ["Claude Code", "Codex", "Gemini CLI", "Claude chat"].map { GlassSegment(value: $0, title: $0) },
                              selection: $agentClient)
                agentClientSetup

            case .verify:
                if store.agentLevel == .off {
                    Label("Sharing is off. Enable read-only summaries in Choose what to share to test the connection.", systemImage: "hand.raised")
                } else {
                    HStack(spacing: 10) {
                        Button("Test Connection", systemImage: "bolt.horizontal") { testAgentConnection() }
                            .glimmerButton(.standard).disabled(testingAgent)
                        if testingAgent { ProgressView().controlSize(.small) }
                        Spacer()
                        Link(destination: URL(string: "https://glimmertoday.ai/mcp")!) {
                            Label("Setup guide", systemImage: "book")
                        }
                        .font(.callout)
                    }
                    if let activity = store.agentActivity, let client = activity.client, let date = activity.clientDate {
                        LabeledContent("Last agent", value: client + " · " + date.formatted(date: .abbreviated, time: .shortened))
                            .font(.callout)
                        if let tool = activity.tool, let toolDate = activity.toolDate {
                            LabeledContent("Last request", value: tool + " · " + toolDate.formatted(date: .abbreviated, time: .shortened))
                                .font(.callout)
                        }
                    }

                }
            }
            if let agentMessage {
                Text(agentMessage).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .onChange(of: agentClient) { agentMessage = nil }
    }

    private func agentToggle(_ title: String, detail: String, isOn: Bool,
                             level: @escaping (Bool) -> AgentAccess.Level) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(title, isOn: Binding(get: { isOn }, set: { enabled in
                do {
                    try store.setAgentLevel(level(enabled))
                    agentError = false
                } catch { agentError = true }
                agentMessage = nil
            }))
            .toggleStyle(.switch).labelsHidden().accessibilityLabel(title).accessibilityHint(detail)
        }
    }

    @ViewBuilder private var agentClientSetup: some View {
        switch agentClient {
        case "Codex":
            copyField("Command", AgentSetup.command)
            copyField("Argument", AgentSetup.argument)
            Text("In Codex Settings → MCP servers, add a STDIO server named glimmer. Paste both fields, save, then type /mcp in a local chat.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
        case "Gemini CLI":
            Text("Choose the project folder you use with Gemini CLI. Glimmer adds its local connection to .gemini/settings.json and keeps your other settings.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Save Gemini connection…", systemImage: "folder.badge.plus") {
                runSetup { try AgentSetup.saveProjectConnection(gemini: true) }
            }.glimmerButton()
            Text("Restart Gemini in that trusted project and enter /mcp to see Glimmer’s tools.")
                .font(.callout)
        case "Claude chat":
            Text("Save the extension, then in the Claude app open Settings → Extensions → Advanced settings → Install Extension… and choose Glimmer.mcpb. Start a new chat and check Connectors.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Save Claude Extension…", systemImage: "puzzlepiece.extension") {
                runSetup(AgentSetup.saveClaudeExtension)
            }
            .glimmerButton(.standard)
        default:
            Text("Save the connection in the folder you open in Claude Code. Then open that folder in Claude’s Code tab, start a new local session on This computer and approve Glimmer.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Save Project Connection…", systemImage: "folder.badge.plus") {
                runSetup { try AgentSetup.saveProjectConnection() }
            }
            .glimmerButton(.standard)
        }
    }

    private func runSetup(_ action: () throws -> String?) {
        do {
            if let result = try action() { agentMessage = result }
        } catch {
            agentMessage = error.localizedDescription
        }
    }

    private func testAgentConnection() {
        testingAgent = true
        agentMessage = nil
        let mode = store.agentLevel == .changes ? "summaries, logging and check-offs" : "read-only summaries"
        Task {
            switch await AgentSetup.testConnection(executable: AgentSetup.command) {
            case .success(let count): agentMessage = "Connection check passed. Glimmer offers \(count) tools, with \(mode) allowed."
            case .failure: agentMessage = "Connection check failed. Quit and reopen Glimmer, then try again."
            }
            testingAgent = false
        }
    }

    private func copyField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(value).font(.callout.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle).help(value)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.inset, in: .rect(cornerRadius: 10))
                Button("Copy \(label.lowercased())", systemImage: "doc.on.doc") {
                    AgentSetup.copy(value)
                    store.notice = "\(label) copied."
                }
                .labelStyle(.iconOnly).glimmerButton(.standard, circle: true)
            }
        }
    }
}
#endif
