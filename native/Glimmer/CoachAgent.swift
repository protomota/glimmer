import Foundation

/// Where Coach and the Toolkit get their replies. The local agents mirror Inkspring's writing agent and
/// OpenTalon's task agent: Glimmer runs the agent's own command line tool with its signed-in session.
enum CoachAgent: String, CaseIterable, Identifiable {
    case device, claude, codex, gemini, server
    var id: Self { self }

    static let preference = "coach.agent"
    static let localAgents: [CoachAgent] = [.claude, .codex, .gemini]

    var title: String {
        switch self {
        case .device: "On this device"
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini CLI"
        case .server: "Local MCP server"
        }
    }

    var symbol: String {
        switch self {
        case .device: "lock.fill"
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .gemini: "diamond.fill"
        case .server: "server.rack"
        }
    }

    var isLocalAgent: Bool { Self.localAgents.contains(self) }

    var guide: URL? {
        switch self {
        case .claude: URL(string: "https://code.claude.com/docs/en/quickstart")
        case .codex: URL(string: "https://learn.chatgpt.com/docs/codex/cli")
        // Gemini runs through Google's Antigravity CLI (agy), as in Inkspring and OpenTalon.
        case .gemini: URL(string: "https://antigravity.google/docs/getting-started?tab=cli")
        default: nil
        }
    }

    /// The same model lists Inkspring offers for its writing agent. The first entry is the top model.
    var models: [CoachModel] {
        switch self {
        case .claude: [.init(id: "claude-fable-5-2", name: "Fable 5.2"), .init(id: "claude-fable-5", name: "Fable 5"),
                       .init(id: "claude-opus-5-5", name: "Opus 5.5"), .init(id: "claude-sonnet-5-5", name: "Sonnet 5.5"),
                       .init(id: "claude-haiku-5-5", name: "Haiku 5.5")]
        case .codex: [.init(id: "gpt-6.2-astra", name: "GPT-6.2 Astra"), .init(id: "gpt-6.2-sol", name: "GPT-6.2 Sol"),
                      .init(id: "gpt-6.1-terra", name: "GPT-6.1 Terra"), .init(id: "gpt-6-luna", name: "GPT-6 Luna")]
        case .gemini: [.init(id: "gemini-4-carbon", name: "Gemini 4 Carbon"), .init(id: "gemini-4-neon", name: "Gemini 4 Neon"),
                       .init(id: "gemini-4-argon", name: "Gemini 4 Argon"), .init(id: "gemini-4-hydrogen", name: "Gemini 4 Hydrogen")]
        default: []
        }
    }

    /// Gemini always needs a model, so its default is the first listed one.
    var defaultModel: String? { self == .gemini ? models.first?.id : nil }

    func efforts(model: String?) -> [String] {
        switch self {
        case .claude: ["low", "medium", "high", "xhigh", "max"]
        case .codex: ["low", "medium", "high", "xhigh"]
        // Antigravity encodes effort in the model ID. Neon and Hydrogen also offer extra high.
        case .gemini: ["gemini-4-neon", "gemini-4-hydrogen"].contains(model ?? defaultModel ?? "")
            ? ["low", "medium", "high", "xhigh"] : ["low", "medium", "high"]
        default: []
        }
    }

    static func effortName(_ effort: String) -> String {
        switch effort {
        case "": "Default"
        case "xhigh": "Extra high"
        default: effort.prefix(1).uppercased() + effort.dropFirst()
        }
    }

    func modelName(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "Agent default" }
        return models.first { $0.id == id }?.name ?? id
    }

    #if os(macOS)
    /// Where each tool installs, in the order Inkspring and OpenTalon look.
    var candidatePaths: [String] {
        let home = CoachAgentRunner.userHome
        return switch self {
        case .claude: [home + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", home + "/.npm-global/bin/claude"]
        case .codex: ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                      "/Applications/Codex.app/Contents/Resources/codex",
                      home + "/.npm-global/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        case .gemini: [home + "/.local/bin/agy", home + "/.antigravity/bin/agy", "/opt/homebrew/bin/agy", "/usr/local/bin/agy"]
        default: []
        }
    }

    var executable: URL? {
        candidatePaths.first(where: FileManager.default.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
    }
    #endif
}

struct CoachModel: Identifiable, Hashable {
    let id: String
    let name: String
}

/// The person's Coach choices, saved per agent like Inkspring's writing model preferences.
struct CoachAgentChoice: Equatable {
    var agent: CoachAgent
    var model: String
    var effort: String
    var timeout: Int

    static let timeouts = [30, 60, 90, 120]
    static func modelKey(_ agent: CoachAgent) -> String { "coach.model.\(agent.rawValue)" }
    static func effortKey(_ agent: CoachAgent) -> String { "coach.effort.\(agent.rawValue)" }
    static let timeoutKey = "coach.timeout"

    static var current: CoachAgentChoice {
        let defaults = UserDefaults.standard
        let agent = defaults.string(forKey: CoachAgent.preference).flatMap(CoachAgent.init(rawValue:)) ?? legacyAgent
        let timeout = defaults.integer(forKey: timeoutKey)
        return .init(agent: agent, model: defaults.string(forKey: modelKey(agent)) ?? "",
                     effort: defaults.string(forKey: effortKey(agent)) ?? "",
                     timeout: timeouts.contains(timeout) ? timeout : 90)
    }

    /// Before the agent picker, a saved MCP address meant Coach used that server.
    private static var legacyAgent: CoachAgent {
        #if os(macOS)
        let endpoint = UserDefaults.standard.string(forKey: CoachMCP.preference) ?? ""
        return CoachMCP.url(endpoint) == nil ? .device : .server
        #else
        .device
        #endif
    }

    /// The model actually sent, or nil for the agent's own default.
    var resolvedModel: String? {
        if agent == .gemini {
            let family = model.isEmpty ? agent.defaultModel ?? "" : model
            let effort = agent.efforts(model: family).contains(effort) ? effort : "high"
            return family + "-" + effort
        }
        return model.isEmpty ? nil : model
    }

    var resolvedEffort: String? {
        agent != .gemini && agent.efforts(model: model).contains(effort) ? effort : nil
    }

    /// A short name for the composer, such as "Claude Code · Opus 5.5".
    var title: String {
        agent.isLocalAgent ? "\(agent.title) · \(agent.modelName(model.isEmpty ? agent.defaultModel : model))" : agent.title
    }

    /// Identifies the conversation partner, so earlier turns from another agent aren't replayed to this one.
    var key: String { "\(agent.rawValue):\(model):\(effort)" }

    /// Coach can use this choice right now on this Mac.
    var isReady: Bool {
        #if os(macOS)
        switch agent {
        case .device: false
        case .server: CoachMCP.url(UserDefaults.standard.string(forKey: CoachMCP.preference) ?? "") != nil
        default: agent.executable != nil
        }
        #else
        false
        #endif
    }
}

/// What Settings shows about recent agent replies. Holds timing and error text only, never questions or replies.
enum CoachAgentLog {
    private static let successKey = "coach.lastSuccess"
    private static let successDetailKey = "coach.lastSuccessDetail"
    private static let failureKey = "coach.lastFailure"
    private static let failureDetailKey = "coach.lastFailureDetail"

    static var lastSuccess: Date? { UserDefaults.standard.object(forKey: successKey) as? Date }
    static var lastSuccessDetail: String? { UserDefaults.standard.string(forKey: successDetailKey) }
    static var lastFailure: Date? { UserDefaults.standard.object(forKey: failureKey) as? Date }
    static var lastFailureDetail: String? { UserDefaults.standard.string(forKey: failureDetailKey) }

    static func success(_ choice: CoachAgentChoice, seconds: Double) {
        UserDefaults.standard.set(Date(), forKey: successKey)
        UserDefaults.standard.set("\(choice.title) answered in \(seconds.formatted(.number.precision(.fractionLength(1)))) s", forKey: successDetailKey)
    }

    static func failure(_ choice: CoachAgentChoice, _ error: Error) {
        UserDefaults.standard.set(Date(), forKey: failureKey)
        UserDefaults.standard.set("\(choice.title): \(error.localizedDescription)", forKey: failureDetailKey)
    }
}

struct CoachAgentFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

#if os(macOS)
/// Runs a local agent's command line tool for one reply, with no tools, skills or MCP servers.
enum CoachAgentRunner {
    /// The person's real home folder. Inside the App Sandbox, NSHomeDirectory() is Glimmer's container.
    static var userHome: String {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir { return String(cString: directory) }
        return NSHomeDirectory()
    }

    /// Sends one prompt and returns the agent's text. Only what's in `instructions` and `prompt` is shared.
    static func run(_ choice: CoachAgentChoice, instructions: String, prompt: String) async throws -> String {
        let agent = choice.agent
        guard agent.isLocalAgent else { throw CoachAgentFailure(message: "Choose Claude Code, Codex or Gemini CLI.") }
        guard let executable = agent.executable else {
            throw CoachAgentFailure(message: "\(agent.title) isn’t installed on this Mac. Install it and sign in, then try again.")
        }
        let root = FileManager.default.temporaryDirectory.appending(path: "GlimmerCoach-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appending(path: "prompt")
        let stdout = root.appending(path: "stdout")
        let stderr = root.appending(path: "stderr")
        let answer = root.appending(path: "answer")

        let arguments: [String]
        switch agent {
        case .claude:
            try Data(prompt.utf8).write(to: input)
            arguments = (choice.resolvedModel.map { ["--model", $0] } ?? []) + (choice.resolvedEffort.map { ["--effort", $0] } ?? [])
                + ["--print", "--restricted", "--output-format", "json", "--tools", "", "--setting-sources", "",
                   "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#, "--disable-slash-commands",
                   "--no-session-persistence", "--system-prompt", instructions + "\n" + isolation]
        case .codex:
            try Data(prompt.utf8).write(to: input)
            arguments = ["-a", "never", "exec"] + (choice.resolvedModel.map { ["--model", $0] } ?? [])
                + ["-c", "developer_instructions=" + tomlString(instructions + "\n" + isolation)]
                + (choice.resolvedEffort.map { ["-c", "model_reasoning_effort=\"\($0)\""] } ?? [])
                + ["--ignore-user-config", "--ignore-rules", "--ephemeral", "--sandbox", "read-only", "--skip-git-repo-check",
                   "-c", "web_search=\"disabled\"", "--disable", "shell_tool", "--disable", "apps", "--disable", "plugins",
                   "--disable", "hooks", "--disable", "multi_agent", "--output-last-message", answer.path, "-"]
        default:
            try geminiProfile(instructions, in: root)
            let message: [String: Any] = ["event": "user", "message": ["content": prompt]]
            try (JSONSerialization.data(withJSONObject: message) + Data([0x0A])).write(to: input)
            arguments = ["--agent", "glimmer-coach", "--model", choice.resolvedModel ?? "", "--sandbox",
                         "--disable-slash-commands", "--print-timeout", "\(max(choice.timeout - 5, 25))s",
                         "--input-format", "stream-json", "--output-format", "stream-json"]
        }
        try Data().write(to: stdout)
        try Data().write(to: stderr)
        let inputHandle = try FileHandle(forReadingFrom: input)
        let outputHandle = try FileHandle(forWritingTo: stdout)
        let errorHandle = try FileHandle(forWritingTo: stderr)
        defer { try? inputHandle.close(); try? outputHandle.close(); try? errorHandle.close() }

        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = root
        process.arguments = arguments
        process.environment = environment(temporary: root)
        process.standardInput = inputHandle
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        try Task.checkCancellation()
        try process.run()
        let deadline = ContinuousClock.now + .seconds(choice.timeout)
        do {
            while process.isRunning && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(100)) }
            try Task.checkCancellation()
        } catch {
            if process.isRunning { process.terminate() }
            throw error
        }
        if process.isRunning {
            process.terminate()
            throw CoachAgentFailure(message: "\(agent.title) didn’t answer within \(choice.timeout) seconds.")
        }
        let output = read(agent == .codex ? answer : stdout)
        guard process.terminationStatus == 0 else {
            let detail = errorLine(read(stderr)) ?? errorLine(output)
            throw CoachAgentFailure(message: "\(agent.title) stopped with code \(process.terminationStatus)"
                                    + (detail.map { ": \($0)" } ?? ". Check its sign-in and the selected model."))
        }
        let text: String?
        switch agent {
        case .claude:
            let result = (try? JSONSerialization.jsonObject(with: output)) as? [String: Any]
            text = result?["is_error"] as? Bool == true ? nil : result?["result"] as? String
        case .codex:
            text = String(data: output, encoding: .utf8)
        default:
            text = geminiResponse(output)
        }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw CoachAgentFailure(message: "\(agent.title) returned no reply. Check its sign-in and the selected model.")
        }
        return String(text.prefix(40_000))
    }

    /// Codex and Antigravity still load the person's global AGENTS.md or GEMINI.md, written for coding work.
    static let isolation = """
    Any AGENTS.md, GEMINI.md or user memory text in this session belongs to the person's coding setup and does not apply here. \
    Never mention skills, memory, files, projects or tools. Reply only as Glimmer.
    """

    /// TOML and JSON escape control characters differently, so encode TOML directly (as Inkspring does).
    private static func tomlString(_ value: String) -> String {
        let escaped = value.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x22: "\\\""
            case 0x5C: "\\\\"
            case 0x00...0x1F, 0x7F: String(format: "\\u%04X", scalar.value)
            default: String(scalar)
            }
        }.joined()
        return "\"" + escaped + "\""
    }

    /// The agent sees the person's real home for its sign-in, and Glimmer's private temporary folder.
    private static func environment(temporary: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for key in ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CODEX_APP_TOOLS_PIPE_PATH", "CODEX_APP_RUNTIME_CLI_PATH",
                    "ELECTRON_RUN_AS_NODE", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CODEX_API_KEY",
                    "GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_APPLICATION_CREDENTIALS", "BWS_ACCESS_TOKEN"] {
            environment.removeValue(forKey: key)
        }
        environment = environment.filter { !$0.key.hasPrefix("GLIMMER_") }
        let home = userHome
        environment["HOME"] = home
        environment["TMPDIR"] = temporary.path + "/"
        environment["CLAUDE_CODE_TMPDIR"] = temporary.path
        environment["PATH"] = [home + "/.local/bin", home + "/.npm-global/bin", "/opt/homebrew/bin", "/usr/local/bin",
                               "/usr/bin", "/bin"].joined(separator: ":")
        return environment
    }

    private static func geminiProfile(_ instructions: String, in root: URL) throws {
        let folder = root.appending(path: ".agents/agents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let profile = """
        ---
        name: glimmer-coach
        description: Reply as Glimmer's coach.
        mainAgent: true
        subagent: false
        tools: []
        mcpServers: []
        plugins: []
        skills: []
        commandExecutionPolicy: "off"
        ---
        \(instructions)
        \(isolation)
        """
        try profile.write(to: folder.appending(path: "glimmer-coach.md"), atomically: true, encoding: .utf8)
    }

    private static func geminiResponse(_ stream: Data) -> String? {
        guard let last = stream.split(separator: 0x0A).last,
              let event = try? JSONSerialization.jsonObject(with: Data(last)) as? [String: Any],
              event["event"] as? String == "result", let result = event["result"] as? [String: Any],
              result["status"] as? String == "SUCCESS" else { return nil }
        return result["response"] as? String
    }

    private static func read(_ url: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 2_000_000)) ?? Data()
    }

    /// The last line that reports an error. Agents echo the prompt to standard error, so other lines stay out.
    private static func errorLine(_ data: Data) -> String? {
        let lines = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
        return lines.last { $0.localizedCaseInsensitiveContains("error") || $0.contains("not permitted") || $0.contains("401") }
            .map { String($0.trimmingCharacters(in: .whitespaces).prefix(240)) }
    }

    /// Pulls the JSON object out of a reply that may be wrapped in a code fence or a sentence.
    static func jsonObject(_ text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any]
    }
}
#endif

#if os(macOS)
/// Sends a Coach or Toolkit request to the chosen agent and records how it went for Settings.
enum CoachAgentRoute {
    static let replyFormat = """
    Reply with only a JSON object: {"answer": "your reply, about 80 words or fewer", "recommendation": "one exact recommendation key from the context, or none"}.
    """

    static func reply(_ choice: CoachAgentChoice, prompt: String) async throws -> CoachReply {
        try await logged(choice) {
            if choice.agent == .server {
                return try await CoachMCP.reply(endpoint: UserDefaults.standard.string(forKey: CoachMCP.preference) ?? "", prompt: prompt)
            }
            let text = try await CoachAgentRunner.run(choice, instructions: CoachGuidanceInstructions.text + "\n" + replyFormat, prompt: prompt)
            if let object = CoachAgentRunner.jsonObject(text), let answer = object["answer"] as? String,
               !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let key = object["recommendation"] as? String
                return CoachReply(answer: answer, recommendation: key == "none" ? nil : key)
            }
            return CoachReply(answer: text, recommendation: nil)
        }
    }

    static func toolkit(_ choice: CoachAgentChoice, tool: ToolkitTool, input: [String: Any], prompt: String) async throws -> [String: Any] {
        try await logged(choice) {
            if choice.agent == .server {
                return try await CoachMCP.toolkit(endpoint: UserDefaults.standard.string(forKey: CoachMCP.preference) ?? "",
                                                  tool: tool, input: input, prompt: prompt)
            }
            let context = String(decoding: (try? JSONSerialization.data(withJSONObject: input)) ?? Data(), as: UTF8.self)
            let text = try await CoachAgentRunner.run(choice, instructions: tool.instructions + "\nReply with only a JSON object shaped like " + tool.replyShape,
                                                      prompt: prompt + "\nInput: " + context)
            guard let object = CoachAgentRunner.jsonObject(text) else {
                throw CoachAgentFailure(message: "\(choice.agent.title) didn’t return a readable result.")
            }
            return object
        }
    }

    /// A short round trip for Settings → Coach → Test Coach.
    static func test(_ choice: CoachAgentChoice) async throws -> String {
        let reply = try await reply(choice, prompt: "This is a connection check. Set answer to \"Ready\" and recommendation to \"none\".")
        return (CoachAgentLog.lastSuccessDetail ?? choice.title) + ": “\(reply.answer.prefix(60))”"
    }

    /// Runs one Test Coach round trip and exits with its result, so support can check an agent headlessly.
    static func runTestCommand(_ arguments: [String]) {
        guard let agent = arguments.first.flatMap(CoachAgent.init(rawValue:)), agent.isLocalAgent else {
            print("Usage: Glimmer --test-coach claude|codex|gemini [model] [effort]")
            exit(2)
        }
        let choice = CoachAgentChoice(agent: agent, model: arguments.count > 1 ? arguments[1] : "",
                                      effort: arguments.count > 2 ? arguments[2] : "", timeout: 120)
        Task {
            do {
                print(try await test(choice))
                exit(0)
            } catch {
                print("Failed: \(error.localizedDescription)")
                exit(1)
            }
        }
        dispatchMain()
    }

    private static func logged<T>(_ choice: CoachAgentChoice, _ operation: () async throws -> T) async throws -> T {
        let start = ContinuousClock.now
        do {
            let value = try await operation()
            let elapsed = (ContinuousClock.now - start).components
            CoachAgentLog.success(choice, seconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
            return value
        } catch {
            if !(error is CancellationError) { CoachAgentLog.failure(choice, error) }
            throw error
        }
    }
}
#endif
