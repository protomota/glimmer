#if os(macOS)
import Security
import SwiftUI

enum CoachMCP {
    static let preference = "coach-mcp-endpoint"
    private static let keychainService = "com.protomota.glimmer.coach-mcp"

    static func url(_ address: String) -> URL? {
        guard let parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "http", parts.host == "127.0.0.1",
              parts.port != nil, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              !parts.path.isEmpty, let url = parts.url else { return nil }
        return url
    }

    private static func keychainQuery(for url: URL) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService, kSecAttrAccount as String: url.absoluteString]
    }

    static func token(for url: URL) -> String? {
        var query = keychainQuery(for: url)
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveToken(_ token: String, for url: URL) throws {
        let query = keychainQuery(for: url)
        let value = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(value) { _, value in value } as CFDictionary, nil) == errSecSuccess else {
                throw CoachConnectionError.keychain
            }
        } else if status != errSecSuccess {
            throw CoachConnectionError.keychain
        }
    }

    static func removeToken(for url: URL) throws {
        let status = SecItemDelete(keychainQuery(for: url) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CoachConnectionError.keychain }
    }

    static func test(_ url: URL, token: String) async throws {
        _ = try await withSession(url, token: token) { connection in
            let result = try await connection.call("tools/list", id: 2)
            guard let tools = result?["tools"] as? [[String: Any]],
                  tools.contains(where: { $0["name"] as? String == "coach_respond" }) else {
                throw CoachConnectionError.missingTool
            }
            return true
        }
    }

    static func reply(endpoint: String, prompt: String) async throws -> CoachReply {
        guard let url = url(endpoint), let token = token(for: url) else { throw CoachConnectionError.invalidConnection }
        return try await withSession(url, token: token) { connection in
            let result = try await connection.call("tools/call", id: 2, params: [
                "name": "coach_respond",
                "arguments": ["instructions": CoachGuidanceInstructions.text, "prompt": prompt]
            ])
            guard result?["isError"] as? Bool != true,
                  let result, let payload = result["structuredContent"] as? [String: Any] else {
                throw CoachConnectionError.invalidReply
            }
            let reply = try JSONDecoder().decode(CoachReply.self, from: JSONSerialization.data(withJSONObject: payload))
            guard !reply.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CoachConnectionError.invalidReply
            }
            return reply
        }
    }

    /// Asks the connected writing agent's `toolkit_respond` tool for a Toolkit result. Only the text the
    /// person typed for this tool is sent, never journal records.
    static func toolkit(endpoint: String, tool: ToolkitTool, input: [String: Any], prompt: String) async throws -> [String: Any] {
        guard let url = url(endpoint), let token = token(for: url) else { throw CoachConnectionError.invalidConnection }
        return try await withSession(url, token: token) { connection in
            let result = try await connection.call("tools/call", id: 2, params: [
                "name": "toolkit_respond",
                "arguments": ["tool": tool.rawValue, "instructions": tool.instructions, "prompt": prompt, "input": input]
            ])
            guard result?["isError"] as? Bool != true,
                  let payload = result?["structuredContent"] as? [String: Any] else {
                throw CoachConnectionError.invalidReply
            }
            return payload
        }
    }

    private static func withSession<T>(_ url: URL, token: String, operation: (CoachMCPSession) async throws -> T) async throws -> T {
        let connection = CoachMCPSession(url: url, token: token)
        defer { connection.finish() }
        try await connection.start()
        return try await operation(connection)
    }
}

private enum CoachConnectionError: Error {
    case invalidConnection, invalidReply, keychain, missingTool
}

/// A one-turn Streamable HTTP client. The peer never receives access to Glimmer tools.
private final class CoachMCPSession: NSObject, URLSessionTaskDelegate {
    let url: URL
    let token: String
    private var sessionID: String?
    private var version = "2025-11-25"
    private lazy var session: URLSession = {
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = 25
        options.timeoutIntervalForResource = 55
        options.httpShouldSetCookies = false
        options.connectionProxyDictionary = [:]
        return URLSession(configuration: options, delegate: self, delegateQueue: nil)
    }()

    init(url: URL, token: String) {
        self.url = url
        self.token = token
    }

    func start() async throws {
        let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26"]
        let response = try await call("initialize", id: 1, params: [
            "protocolVersion": version,
            "capabilities": [String: String](),
            "clientInfo": ["name": "Glimmer Coach", "version": "1.0"]
        ])
        guard let agreed = response?["protocolVersion"] as? String, supportedVersions.contains(agreed) else {
            throw CoachConnectionError.invalidConnection
        }
        version = agreed
        _ = try await call("notifications/initialized")
    }

    func call(_ method: String, id: Int? = nil, params: [String: Any]? = nil) async throws -> [String: Any]? {
        var request = makeRequest(method: "POST")
        var body: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let id { body["id"] = id }
        if let params { body["params"] = params }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw CoachConnectionError.invalidConnection
        }
        if method == "initialize" { sessionID = http.value(forHTTPHeaderField: "Mcp-Session-Id") }
        guard let id else { return nil }

        if http.mimeType == "text/event-stream" {
            var event = Data()
            var line = Data()
            for try await byte in bytes {
                if byte != 0x0A {
                    guard line.count < 64_000 else { throw CoachConnectionError.invalidReply }
                    line.append(byte)
                    continue
                }
                if line.last == 0x0D { line.removeLast() }
                if line.isEmpty {
                    if let result = try decode(event, id: id) { return result }
                    event.removeAll(keepingCapacity: true)
                } else if line.starts(with: "data:".utf8) {
                    let field = line.dropFirst(5)
                    let value = field.first == 0x20 ? field.dropFirst() : field
                    guard event.count + value.count < 64_000 else { throw CoachConnectionError.invalidReply }
                    if !event.isEmpty { event.append(0x0A) }
                    event.append(contentsOf: value)
                }
                line.removeAll(keepingCapacity: true)
            }
        } else if http.mimeType == "application/json" {
            var data = Data()
            for try await byte in bytes {
                guard data.count < 64_000 else { throw CoachConnectionError.invalidReply }
                data.append(byte)
            }
            if let result = try decode(data, id: id) { return result }
        }
        throw CoachConnectionError.invalidReply
    }

    private func decode(_ data: Data, id: Int) throws -> [String: Any]? {
        guard !data.isEmpty else { return nil }
        let packet = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard packet?["id"] as? Int == id else { return nil }
        guard let result = packet?["result"] as? [String: Any] else { throw CoachConnectionError.invalidReply }
        return result
    }

    private func makeRequest(method: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        request.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version")
        return request
    }

    func finish() {
        if sessionID != nil {
            var request = makeRequest(method: "DELETE")
            request.timeoutInterval = 3
            session.dataTask(with: request).resume()
        }
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// The address and token for a local MCP server that provides coach_respond, shown when Coach uses one.
struct CoachServerFields: View {
    @AppStorage(CoachMCP.preference) private var endpoint = ""
    @State private var address = ""
    @State private var token = ""
    @State private var status: String?
    @State private var probe: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect a local MCP server that provides a coach_respond tool, and optionally toolkit_respond for the Toolkit.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Local MCP URL", text: $address, prompt: Text("http://127.0.0.1:8400/mcp"))
                .glimmerField()
            SecureField(endpoint.isEmpty ? "Server token" : "Replace server token", text: $token).glimmerField()
            HStack {
                Button(probe == nil ? "Test and connect" : "Testing…", action: connect)
                    .glimmerButton()
                    .disabled(probe != nil || CoachMCP.url(address) == nil || token.trimmingCharacters(in: .whitespaces).isEmpty)
                if !endpoint.isEmpty {
                    Button("Disconnect", action: disconnect).glimmerButton()
                        .disabled(probe != nil)
                }
            }
            if let status { Text(status).font(.callout).foregroundStyle(.secondary) }
        }
        .onAppear { address = endpoint }
        .onDisappear { probe?.cancel() }
    }

    private func connect() {
        guard let url = CoachMCP.url(address) else { return }
        let secret = token.trimmingCharacters(in: .whitespacesAndNewlines)
        probe = Task {
            defer { probe = nil }
            do {
                try await CoachMCP.test(url, token: secret)
                try Task.checkCancellation()
                try CoachMCP.saveToken(secret, for: url)
                if let old = CoachMCP.url(endpoint), old != url { try? CoachMCP.removeToken(for: old) }
                endpoint = url.absoluteString
                token = ""
                status = "Connected. Coach will use this server on this Mac."
            } catch CoachConnectionError.missingTool {
                status = "The server answered, but couldn’t find a coach_respond tool."
            } catch {
                if !Task.isCancelled { status = "Couldn’t connect. Check the local server address and token." }
            }
        }
    }

    private func disconnect() {
        if let url = CoachMCP.url(endpoint) { try? CoachMCP.removeToken(for: url) }
        endpoint = ""
        token = ""
        status = "Disconnected. Choose another way for Coach to reply."
    }
}
#endif
