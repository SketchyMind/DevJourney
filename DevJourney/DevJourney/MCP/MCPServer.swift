import Foundation
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

/// MCP Server that exposes DevJourney's board, project, and workflow operations
/// as tools that any MCP-compatible AI client (Claude Desktop, Cursor, etc.) can use.
///
/// Protocol: JSON-RPC 2.0 over stdio (stdin/stdout).
@MainActor
final class MCPServer {
    var isRunning = false
    var connectedClient: String?

    private static let sharedToolRegistry = MCPToolRegistry()

    private var modelContainer: ModelContainer?
    private var projectService: ProjectService?
    private var gitHubService: GitHubService?
    private var workflowService: TicketWorkflowService?
    private var inputTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var initializeTimeoutTask: Task<Void, Never>?
    private var negotiatedEncoding: MCPMessageEncoding = .contentLength
    private var negotiatedProtocolVersion = "2024-11-05"
    private var didInitialize = false
    private let toolRegistry: MCPToolRegistry
    private let terminationHandler: @MainActor () -> Void
    private let traceFilePath: String?
    private let connectionStatusStore: MCPConnectionStatusStore

    convenience init(
        terminationHandler: @escaping @MainActor () -> Void = {
            #if canImport(AppKit)
            NSApp.terminate(nil)
            #else
            Foundation.exit(EXIT_SUCCESS)
            #endif
        }
    ) {
        self.init(
            connectionStatusStore: .shared,
            terminationHandler: terminationHandler
        )
    }

    convenience init(connectionStatusStore: MCPConnectionStatusStore) {
        self.init(
            connectionStatusStore: connectionStatusStore,
            terminationHandler: {
                #if canImport(AppKit)
                NSApp.terminate(nil)
                #else
                Foundation.exit(EXIT_SUCCESS)
                #endif
            }
        )
    }

    init(
        connectionStatusStore: MCPConnectionStatusStore,
        terminationHandler: @escaping @MainActor () -> Void
    ) {
        toolRegistry = Self.sharedToolRegistry
        self.connectionStatusStore = connectionStatusStore
        self.terminationHandler = terminationHandler
        self.traceFilePath = ProcessInfo.processInfo.environment["DEVJOURNEY_MCP_TRACE_FILE"]
    }

    func configure(
        modelContainer: ModelContainer,
        projectService: ProjectService,
        gitHubService: GitHubService,
        workflowService: TicketWorkflowService
    ) {
        self.modelContainer = modelContainer
        self.projectService = projectService
        self.gitHubService = gitHubService
        self.workflowService = workflowService
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        connectedClient = nil
        negotiatedEncoding = .contentLength
        negotiatedProtocolVersion = "2024-11-05"
        didInitialize = false
        connectionStatusStore.clear()

        inputTask = Task.detached { [weak self] in
            let stdin = FileHandle.standardInput
            var buffer = Data()

            while !Task.isCancelled {
                let chunk = stdin.availableData
                guard !chunk.isEmpty else {
                    await self?.handleInputClosed()
                    return
                }
                buffer.append(chunk)

                while let extracted = Self.extractMessage(from: buffer) {
                    buffer = extracted.remaining
                    if extracted.message.isEmpty {
                        continue
                    }
                    await self?.handleMessage(extracted.message, encoding: extracted.encoding)
                }
            }
        }

        initializeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, self.isRunning, !self.didInitialize else { return }
            self.stop()
            self.terminationHandler()
        }
    }

    func handleInputClosed() {
        guard isRunning else { return }
        stop()
        terminationHandler()
    }

    func stop() {
        inputTask?.cancel()
        inputTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        initializeTimeoutTask?.cancel()
        initializeTimeoutTask = nil
        isRunning = false
        connectedClient = nil
        didInitialize = false
        connectionStatusStore.clear()
    }

    // MARK: - Message Framing

    nonisolated static func extractMessage(from data: Data) -> MCPExtractedMessage? {
        if let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) {
            let headerData = data[data.startIndex..<headerEnd.lowerBound]
            if let headerString = String(data: headerData, encoding: .utf8),
               let contentLengthLine = headerString.split(separator: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length:") }),
               let length = Int(contentLengthLine.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "") {
                let bodyStart = headerEnd.upperBound
                let bodyEnd = data.index(bodyStart, offsetBy: length, limitedBy: data.endIndex) ?? data.endIndex
                guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return nil }

                let messageData = data[bodyStart..<bodyEnd]
                let remaining = data[bodyEnd...]
                return MCPExtractedMessage(
                    message: Data(messageData),
                    remaining: Data(remaining),
                    encoding: .contentLength
                )
            }
        }

        guard let newline = data.firstIndex(of: 0x0A) else { return nil }
        let lineData = Data(data[data.startIndex..<newline])
        let remainingStart = data.index(after: newline)
        let remaining = Data(data[remainingStart...])
        let trimmed = lineData.trimmingLeadingAndTrailingWhitespaceAndCR()

        guard !trimmed.isEmpty else {
            return MCPExtractedMessage(
                message: Data(),
                remaining: remaining,
                encoding: .newlineDelimited
            )
        }

        guard (try? JSONSerialization.jsonObject(with: trimmed)) != nil else {
            return nil
        }

        return MCPExtractedMessage(
            message: trimmed,
            remaining: remaining,
            encoding: .newlineDelimited
        )
    }

    // MARK: - Message Handling

    private func handleMessage(_ data: Data, encoding: MCPMessageEncoding) async {
        negotiatedEncoding = encoding
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String
        else {
            trace("invalid-request")
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["id"] {
                sendError(id: id, code: -32600, message: "Invalid Request")
            }
            return
        }

        trace("recv \(method)")

        let id = json["id"] // may be nil for notifications
        let params = json["params"] as? [String: Any] ?? [:]

        let result: Any?

        switch method {
        case "initialize":
            result = handleInitialize(params)
        case "notifications/initialized":
            return // notification, no response
        case "initialized":
            return // notification, no response
        case "tools/list":
            result = handleToolsList()
        case "tools/call":
            result = await handleToolCall(params)
        case "resources/list":
            result = handleResourcesList()
        case "resources/templates/list":
            result = handleResourceTemplatesList()
        case "prompts/list":
            result = handlePromptsList()
        case "prompts/get":
            result = handlePromptsGet(params)
        case "ping":
            result = [String: Any]()
        default:
            if let id {
                trace("error \(method) method-not-found")
                sendError(id: id, code: -32601, message: "Method not found: \(method)")
            }
            return
        }

        if let id, let result {
            trace("send \(method)")
            sendResponse(id: id, result: result)
        }
    }

    // MARK: - Protocol Handlers

    private func handleInitialize(_ params: [String: Any]) -> [String: Any] {
        didInitialize = true
        initializeTimeoutTask?.cancel()
        initializeTimeoutTask = nil
        if let clientInfo = params["clientInfo"] as? [String: Any] {
            connectedClient = clientInfo["name"] as? String
        }
        if let clientProtocolVersion = params["protocolVersion"] as? String {
            negotiatedProtocolVersion = Self.negotiateProtocolVersion(clientProtocolVersion)
        }
        startHeartbeat()

        return [
            "protocolVersion": negotiatedProtocolVersion,
            "capabilities": [
                "tools": [String: Any](),
                "resources": [String: Any](),
                "prompts": [String: Any]()
            ],
            "serverInfo": [
                "name": "devjourney",
                "version": "1.0.0"
            ]
        ]
    }

    private func handleToolsList() -> [String: Any] {
        ["tools": toolRegistry.allToolDefinitions()]
    }

    private func handleToolCall(_ params: [String: Any]) async -> [String: Any] {
        guard let name = params["name"] as? String else {
            return errorContent("Missing tool name")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]

        guard let handler = toolRegistry.handler(for: name) else {
            return errorContent("Unknown tool: \(name)")
        }

        guard let container = modelContainer,
              let service = projectService,
              let workflowService = workflowService else {
            return errorContent("Server not configured")
        }

        let context = MCPToolContext(
            modelContainer: container,
            projectService: service,
            gitHubService: gitHubService ?? GitHubService(),
            workflowService: workflowService
        )

        do {
            let result = try await handler(arguments, context)
            return [
                "content": [
                    ["type": "text", "text": result]
                ]
            ]
        } catch {
            return errorContent("Tool error: \(error.localizedDescription)")
        }
    }

    private func handleResourcesList() -> [String: Any] {
        ["resources": [[String: Any]]()]
    }

    private func handleResourceTemplatesList() -> [String: Any] {
        ["resourceTemplates": [[String: Any]]()]
    }

    private func handlePromptsList() -> [String: Any] {
        ["prompts": MCPPromptTemplates.allPromptDefinitions()]
    }

    private func handlePromptsGet(_ params: [String: Any]) -> [String: Any]? {
        guard let name = params["name"] as? String else { return nil }
        let arguments = params["arguments"] as? [String: Any] ?? [:]
        return MCPPromptTemplates.getPrompt(name: name, arguments: arguments)
    }

    func initializePayload(
        clientInfo: [String: Any]? = nil,
        protocolVersion: String = "2024-11-05"
    ) -> [String: Any] {
        var params: [String: Any] = [:]
        if let clientInfo {
            params["clientInfo"] = clientInfo
        }
        params["protocolVersion"] = protocolVersion
        return handleInitialize(params)
    }

    func toolDefinitionsPayload() -> [String: Any] {
        handleToolsList()
    }

    func promptDefinitionsPayload() -> [String: Any] {
        handlePromptsList()
    }

    func resourceTemplateDefinitionsPayload() -> [String: Any] {
        handleResourceTemplatesList()
    }

    func promptPayload(name: String, arguments: [String: Any] = [:]) -> [String: Any]? {
        handlePromptsGet([
            "name": name,
            "arguments": arguments
        ])
    }

    func callToolLocally(name: String, arguments: [String: Any] = [:]) async -> [String: Any] {
        await handleToolCall([
            "name": name,
            "arguments": arguments
        ])
    }

    // MARK: - Response Helpers

    private func errorContent(_ message: String) -> [String: Any] {
        [
            "content": [
                ["type": "text", "text": message]
            ],
            "isError": true
        ]
    }

    private func sendResponse(id: Any, result: Any) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ]
        sendJSON(response)
    }

    private func sendError(id: Any, code: Int, message: String) {
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "error": [
                "code": code,
                "message": message
            ]
        ]
        sendJSON(response)
    }

    private func sendJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }

        switch negotiatedEncoding {
        case .contentLength:
            guard let json = String(data: data, encoding: .utf8) else { return }
            let message = "Content-Length: \(data.count)\r\n\r\n\(json)"
            if let messageData = message.data(using: .utf8) {
                FileHandle.standardOutput.write(messageData)
            }
        case .newlineDelimited:
            var payload = data
            payload.append(0x0A)
            FileHandle.standardOutput.write(payload)
        }
    }

    private func trace(_ message: String) {
        guard let traceFilePath, !traceFilePath.isEmpty else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: traceFilePath) == false {
            FileManager.default.createFile(atPath: traceFilePath, contents: nil)
        }
        guard let handle = FileHandle(forWritingAtPath: traceFilePath) else { return }
        defer { try? handle.close() }
        let _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task {
            while !Task.isCancelled {
                try? connectionStatusStore.write(clientName: connectedClient)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

enum MCPMessageEncoding: Equatable {
    case contentLength
    case newlineDelimited
}

struct MCPExtractedMessage {
    let message: Data
    let remaining: Data
    let encoding: MCPMessageEncoding
}

private extension MCPServer {
    static func negotiateProtocolVersion(_ clientVersion: String) -> String {
        switch clientVersion {
        case "2025-11-25":
            return "2025-11-25"
        case "2024-11-05":
            return "2024-11-05"
        default:
            return "2025-11-25"
        }
    }
}

private extension Data {
    nonisolated func trimmingLeadingAndTrailingWhitespaceAndCR() -> Data {
        var start = startIndex
        var end = endIndex

        while start < end, [0x09, 0x0D, 0x20].contains(self[start]) {
            start = index(after: start)
        }

        while end > start {
            let beforeEnd = index(before: end)
            if [0x09, 0x0D, 0x20].contains(self[beforeEnd]) {
                end = beforeEnd
            } else {
                break
            }
        }

        return Data(self[start..<end])
    }
}
