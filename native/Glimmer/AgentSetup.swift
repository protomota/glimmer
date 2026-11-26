#if os(macOS)
import AppKit
import Foundation
import UniformTypeIdentifiers

/// Connection setup for Claude Code, Codex and Claude chat. Every step is an explicit action in
/// Settings; Glimmer never edits an agent's configuration on its own.
@MainActor
enum AgentSetup {
    static var command: String { Bundle.main.executableURL?.path ?? "/Applications/Glimmer.app/Contents/MacOS/Glimmer" }
    static let argument = AgentAccess.argument

    enum SetupError: LocalizedError {
        case invalidConfiguration, unsafeFile, changedFile, exportFailed

        var errorDescription: String? {
            switch self {
            case .invalidConfiguration: "The existing configuration isn’t a valid MCP configuration, so Glimmer left it unchanged."
            case .unsafeFile: "Choose a folder whose configuration is a regular file, not a link or folder."
            case .changedFile: "The project’s .mcp.json changed while saving. Try again."
            case .exportFailed: "Glimmer couldn’t save the Claude extension. Choose another location and try again."
            }
        }
    }

    // MARK: Claude Code

    nonisolated static func mergedProjectConfiguration(existing: Data?, command: String) throws -> (data: Data, replaces: Bool) {
        let entry: [String: Any] = ["type": "stdio", "command": command, "args": [AgentAccess.argument]]
        var root: [String: Any] = [:]
        if let existing, !existing.isEmpty {
            guard let parsed = try? JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
                throw SetupError.invalidConfiguration
            }
            root = parsed
        }
        if let servers = root["mcpServers"], !(servers is [String: Any]) { throw SetupError.invalidConfiguration }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        let replaces = servers["glimmer"].map { !NSDictionary(dictionary: ["entry": $0]).isEqual(to: ["entry": entry]) } ?? false
        servers["glimmer"] = entry
        root["mcpServers"] = servers
        return (try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), replaces)
    }

    static func saveProjectConnection(gemini: Bool = false) throws -> String? {
        let panel = NSOpenPanel()
        let client = gemini ? "Gemini CLI" : "Claude Code"
        let path = gemini ? ".gemini/settings.json" : ".mcp.json"
        panel.title = "Choose your \(client) project folder"
        panel.message = "Glimmer adds itself to \(path) in this folder. Other servers in the file stay as they are."
        panel.prompt = "Save Connection"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return nil }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        if gemini {
            let directory = folder.appending(path: ".gemini", directoryHint: .isDirectory)
            if (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw SetupError.unsafeFile }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let file = folder.appending(path: path)
        let existing = try readConfiguration(file)
        let merged = try mergedProjectConfiguration(existing: existing, command: command)
        if merged.replaces {
            let alert = NSAlert()
            alert.messageText = "Replace this project’s Glimmer connection?"
            alert.informativeText = "Only the glimmer entry changes, so it points at this copy of Glimmer. Other MCP servers are kept."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        }
        guard try readConfiguration(file) == existing else { throw SetupError.changedFile }
        try merged.data.write(to: file, options: .atomic)
        return "Saved to \(folder.lastPathComponent)/\(path). Start a new \(client) session in that folder."
    }

    private static func readConfiguration(_ file: URL) throws -> Data? {
        // Check the link itself first, including a broken one.
        if let values = try? file.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]),
           values.isSymbolicLink == true || values.isDirectory == true { throw SetupError.unsafeFile }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try Data(contentsOf: file)
    }

    // MARK: Claude chat

    static func saveClaudeExtension() throws -> String? {
        let panel = NSSavePanel()
        panel.title = "Save the Claude extension"
        panel.nameFieldStringValue = "Glimmer.mcpb"
        panel.allowedContentTypes = [UTType(filenameExtension: "mcpb") ?? .data]
        panel.message = "Install this file in the Claude app under Settings → Extensions. It holds no journal data."
        guard panel.runModal() == .OK, let destination = panel.url else { return nil }

        let staging = FileManager.default.temporaryDirectory.appending(path: "Glimmer-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try Data(extensionServer.utf8).write(to: staging.appending(path: "server.js"))
        try extensionManifest(command: command).write(to: staging.appending(path: "manifest.json"))
        guard let tiff = NSApplication.shared.applicationIconImage?.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { throw SetupError.exportFailed }
        try png.write(to: staging.appending(path: "icon.png"))

        // Coordinated reading "for uploading" hands back a zip of the folder, which is what an .mcpb is.
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: staging, options: .forUploading, error: &coordinationError) { zip in
            do { try Data(contentsOf: zip).write(to: destination, options: .atomic) } catch { copyError = error }
        }
        if coordinationError != nil || copyError != nil { throw SetupError.exportFailed }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
        return "Glimmer.mcpb saved. In the Claude app, open Settings → Extensions and install it, then start a new chat."
    }

    nonisolated static func extensionManifest(command: String) throws -> Data {
        let manifest: [String: Any] = [
            "manifest_version": "0.3",
            "name": "glimmer",
            "display_name": "Glimmer",
            "version": AgentAccess.version,
            "description": "Read your Glimmer attention summaries and log moments on your Mac.",
            "long_description": "Connect Claude chat to the Glimmer journal on this Mac. Glimmer Settings → Agent access controls what Claude can read and change. Claude may send what it reads to Anthropic under Claude's terms.",
            "author": ["name": "Protomota, LLC", "url": "https://protomota.com"],
            "homepage": "https://glimmertoday.ai",
            "support": "https://glimmertoday.ai/mcp",
            "privacy_policies": ["https://glimmertoday.ai/privacy#mcp"],
            "icon": "icon.png",
            "server": [
                "type": "node",
                "entry_point": "server.js",
                "mcp_config": [
                    "command": "node",
                    "args": ["${__dirname}/server.js"],
                    "env": ["GLIMMER_APP_EXECUTABLE": command]
                ]
            ],
            "tools": AgentAccess.tools.map { ["name": $0["name"] ?? "", "description": $0["description"] ?? ""] },
            "compatibility": ["platforms": ["darwin"], "runtimes": ["node": ">=18.0.0"]]
        ]
        return try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Claude supplies Node. The script only starts Glimmer's own `--mcp` server and passes messages through.
    nonisolated static let extensionServer = """
    'use strict';
    const { spawn } = require('node:child_process');
    const fs = require('node:fs');

    const candidates = [process.env.GLIMMER_APP_EXECUTABLE, '/Applications/Glimmer.app/Contents/MacOS/Glimmer']
      .filter(path => typeof path === 'string' && path.endsWith('/Glimmer.app/Contents/MacOS/Glimmer'));
    const executable = candidates.find(path => fs.existsSync(path));
    if (!executable) {
      process.stderr.write('Install Glimmer for Mac in Applications, then turn on Settings → Agent access.\\n');
      process.exit(1);
    }

    const glimmer = spawn(executable, ['--mcp'], { stdio: ['pipe', 'pipe', 'inherit'] });
    process.stdin.pipe(glimmer.stdin);
    glimmer.stdout.pipe(process.stdout);
    process.stdin.on('end', () => glimmer.stdin.end());
    glimmer.on('exit', code => process.exit(code ?? 0));
    glimmer.on('error', () => {
      process.stderr.write('Glimmer could not start. Open Glimmer once, then try again.\\n');
      process.exit(1);
    });
    """

    // MARK: Connection check

    /// Starts this copy of Glimmer the way an agent does and lists its tools.
    nonisolated static func testConnection(executable: String) async -> Result<Int, Error> {
        await Task.detached { listTools(executable: executable) }.value
    }

    private nonisolated static func listTools(executable: String) -> Result<Int, Error> {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = [AgentAccess.argument]
            let input = Pipe(), output = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let requests = [
                    #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"\#(AgentAccess.checkClient)","version":"1"}}}"#,
                    #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
                    #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#
                ]
                input.fileHandleForWriting.write(Data((requests.joined(separator: "\n") + "\n").utf8))
                try input.fileHandleForWriting.close()
                let deadline = DispatchTime.now() + .seconds(10)
                let finished = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in finished.signal() }
                if finished.wait(timeout: deadline) == .timedOut { process.terminate() }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                for line in data.split(separator: 10) {
                    guard let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                          message["id"] as? Int == 2,
                          let tools = (message["result"] as? [String: Any])?["tools"] as? [Any] else { continue }
                    return .success(tools.count)
                }
                return .failure(SetupError.exportFailed)
            } catch {
                return .failure(error)
            }
    }

    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
#endif
