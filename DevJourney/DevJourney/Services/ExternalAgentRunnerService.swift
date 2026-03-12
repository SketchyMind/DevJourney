import Foundation

enum ExternalAgentClient: String, Sendable {
    case claudeCode
    case codex

    var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        }
    }

    var providerDisplayName: String {
        "\(displayName) via MCP"
    }

    var modelDisplayName: String {
        providerDisplayName
    }

    var executableName: String {
        switch self {
        case .claudeCode:
            return "claude"
        case .codex:
            return "codex"
        }
    }

    static func fromConnectedClientName(_ value: String?) -> ExternalAgentClient? {
        let lowered = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !lowered.isEmpty else { return nil }
        if lowered.contains("codex") {
            return .codex
        }
        if lowered.contains("claude") {
            return .claudeCode
        }
        return nil
    }
}

struct ExternalAgentRunResult: Sendable {
    let client: ExternalAgentClient
    let terminationStatus: Int32
    let finalMessage: String
    let errorOutput: String
}

@MainActor
class ExternalAgentRunnerService {
    private let fileManager: FileManager
    private let environmentProvider: @Sendable () -> [String: String]
    private let launcherPathProvider: @Sendable () -> String
    private let temporaryDirectoryProvider: @Sendable () -> URL

    init(
        fileManager: FileManager = .default,
        environmentProvider: @escaping @Sendable () -> [String: String] = {
            ProcessInfo.processInfo.environment
        },
        launcherPathProvider: @escaping @Sendable () -> String = {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            return root
                .appendingPathComponent("DevJourney", isDirectory: true)
                .appendingPathComponent("devjourney-mcp", isDirectory: false)
                .path
        },
        temporaryDirectoryProvider: @escaping @Sendable () -> URL = {
            FileManager.default.temporaryDirectory
        }
    ) {
        self.fileManager = fileManager
        self.environmentProvider = environmentProvider
        self.launcherPathProvider = launcherPathProvider
        self.temporaryDirectoryProvider = temporaryDirectoryProvider
    }

    func resolvePreferredClient(
        connectionStatus: MCPConnectionStatusSnapshot,
        claudeStatus: ClaudeMCPRegistrationStatus
    ) -> ExternalAgentClient? {
        if connectionStatus.isClientConnected(),
           let connected = ExternalAgentClient.fromConnectedClientName(connectionStatus.clientName),
           executablePath(for: connected) != nil {
            return connected
        }

        if executablePath(for: .claudeCode) != nil,
           claudeStatus.mode != .unavailable {
            return .claudeCode
        }

        if executablePath(for: .codex) != nil {
            return .codex
        }

        return executablePath(for: .claudeCode) != nil ? .claudeCode : nil
    }

    func run(
        client: ExternalAgentClient,
        projectDirectory: String,
        prompt: String,
        onThought: @escaping @MainActor (String) -> Void,
        onAssistantDelta: @escaping @MainActor (String) -> Void
    ) async throws -> ExternalAgentRunResult {
        guard let executablePath = executablePath(for: client) else {
            throw ExternalAgentRunnerError.clientUnavailable(client.displayName)
        }

        let configURL = try writeMCPConfigIfNeeded(for: client)
        let outputURL = temporaryDirectoryProvider()
            .appendingPathComponent("devjourney-\(client.rawValue)-\(UUID().uuidString).txt", isDirectory: false)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.currentDirectoryURL = URL(fileURLWithPath: projectDirectory, isDirectory: true)
        process.environment = cliLocator().augmentedEnvironment()
        process.arguments = arguments(
            for: client,
            projectDirectory: projectDirectory,
            prompt: prompt,
            mcpConfigURL: configURL,
            outputURL: outputURL
        )

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let stderrCollector = StreamCollector()
        let assistantCollector = StreamCollector()
        let stdoutTask = Task {
            try await self.consumeOutput(
                from: stdout.fileHandleForReading,
                client: client,
                isErrorStream: false,
                collector: nil,
                assistantCollector: assistantCollector,
                onThought: onThought,
                onAssistantDelta: onAssistantDelta
            )
        }
        let stderrTask = Task {
            try await self.consumeOutput(
                from: stderr.fileHandleForReading,
                client: client,
                isErrorStream: true,
                collector: stderrCollector,
                assistantCollector: assistantCollector,
                onThought: onThought,
                onAssistantDelta: onAssistantDelta
            )
        }

        let terminationTask = Task<Int32, Error> {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { process in
                    continuation.resume(returning: process.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        let terminationStatus = try await withTaskCancellationHandler {
            try await terminationTask.value
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }

        _ = try? await stdoutTask.value
        _ = try? await stderrTask.value

        let finalMessage: String
        if client == .claudeCode {
            finalMessage = (await assistantCollector.contents()).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            finalMessage = ((try? String(contentsOf: outputURL, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
        }
        let errorOutput = (await stderrCollector.contents())
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if client != .claudeCode {
            try? fileManager.removeItem(at: outputURL)
        }
        if let configURL {
            try? fileManager.removeItem(at: configURL)
        }

        return ExternalAgentRunResult(
            client: client,
            terminationStatus: terminationStatus,
            finalMessage: finalMessage,
            errorOutput: errorOutput
        )
    }

    private func consumeOutput(
        from handle: FileHandle,
        client: ExternalAgentClient,
        isErrorStream: Bool,
        collector: StreamCollector?,
        assistantCollector: StreamCollector,
        onThought: @escaping @MainActor (String) -> Void,
        onAssistantDelta: @escaping @MainActor (String) -> Void
    ) async throws {
        for try await line in handle.bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let collector {
                await collector.append(trimmed + "\n")
            }

            if let payload = jsonObject(from: trimmed) {
                await handleStructuredLine(
                    payload,
                    client: client,
                    assistantCollector: assistantCollector,
                    onThought: onThought,
                    onAssistantDelta: onAssistantDelta
                )
                continue
            }

            if isNoise(trimmed) {
                continue
            }

            await MainActor.run {
                onThought(trimmed)
            }
        }
    }

    private func handleStructuredLine(
        _ payload: [String: Any],
        client: ExternalAgentClient,
        assistantCollector: StreamCollector,
        onThought: @escaping @MainActor (String) -> Void,
        onAssistantDelta: @escaping @MainActor (String) -> Void
    ) async {
        switch client {
        case .claudeCode:
            await handleClaudeLine(
                payload,
                assistantCollector: assistantCollector,
                onThought: onThought,
                onAssistantDelta: onAssistantDelta
            )
        case .codex:
            await handleCodexLine(
                payload,
                assistantCollector: assistantCollector,
                onThought: onThought,
                onAssistantDelta: onAssistantDelta
            )
        }
    }

    private func handleClaudeLine(
        _ payload: [String: Any],
        assistantCollector: StreamCollector,
        onThought: @escaping @MainActor (String) -> Void,
        onAssistantDelta: @escaping @MainActor (String) -> Void
    ) async {
        if let type = payload["type"] as? String,
           type == "stream_event",
           let event = payload["event"] as? [String: Any],
           let eventType = event["type"] as? String {
            switch eventType {
            case "content_block_start":
                if let contentBlock = event["content_block"] as? [String: Any],
                   contentBlock["type"] as? String == "tool_use",
                   let name = contentBlock["name"] as? String {
                    await MainActor.run {
                        onThought("Calling \(name)")
                    }
                }
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   delta["type"] as? String == "text_delta",
                   let text = delta["text"] as? String,
                   !text.isEmpty {
                    await assistantCollector.append(text)
                    await MainActor.run {
                        onAssistantDelta(text)
                    }
                }
            default:
                break
            }
        }

        if let type = payload["type"] as? String,
           type == "assistant",
           let message = payload["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            let text = content
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "")
            let existingText = await assistantCollector.contents()
            if !text.isEmpty,
               existingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await assistantCollector.append(text)
            }
        }

        if let type = payload["type"] as? String,
           type == "result",
           payload["subtype"] as? String == "success" {
            await MainActor.run {
                onThought("Claude Code completed the stage run.")
            }
        }
    }

    private func handleCodexLine(
        _ payload: [String: Any],
        assistantCollector: StreamCollector,
        onThought: @escaping @MainActor (String) -> Void,
        onAssistantDelta: @escaping @MainActor (String) -> Void
    ) async {
        guard let type = payload["type"] as? String else { return }

        switch type {
        case "item.started":
            if let item = payload["item"] as? [String: Any],
               item["type"] as? String == "mcp_tool_call",
               let tool = item["tool"] as? String {
                await MainActor.run {
                    onThought("Calling \(tool)")
                }
            }
        case "item.completed":
            guard let item = payload["item"] as? [String: Any],
                  let itemType = item["type"] as? String else { return }
            switch itemType {
            case "agent_message":
                if let text = item["text"] as? String,
                   !text.isEmpty {
                    await assistantCollector.append(text)
                    await MainActor.run {
                        onAssistantDelta(text)
                    }
                }
            case "mcp_tool_call":
                if let tool = item["tool"] as? String {
                    await MainActor.run {
                        onThought("Completed \(tool)")
                    }
                }
            default:
                break
            }
        default:
            break
        }
    }

    private func arguments(
        for client: ExternalAgentClient,
        projectDirectory: String,
        prompt: String,
        mcpConfigURL: URL?,
        outputURL: URL
    ) -> [String] {
        switch client {
        case .claudeCode:
            var arguments = [
                "-p",
                "--verbose",
                "--output-format", "stream-json",
                "--include-partial-messages",
                "--permission-mode", "bypassPermissions"
            ]
            if let mcpConfigURL {
                arguments.append(contentsOf: [
                    "--strict-mcp-config",
                    "--mcp-config", mcpConfigURL.path
                ])
            }
            arguments.append("--")
            arguments.append(prompt)
            return arguments

        case .codex:
            return [
                "-a", "never",
                "-s", "workspace-write",
                "-c", #"mcp_servers.devjourney.command="\#(launcherPathProvider())""#,
                "-c", #"mcp_servers.devjourney.args=["--mcp"]"#,
                "exec",
                "-C", projectDirectory,
                "--json",
                "-o", outputURL.path,
                prompt
            ]
        }
    }

    private func writeMCPConfigIfNeeded(for client: ExternalAgentClient) throws -> URL? {
        guard client == .claudeCode else { return nil }

        let configURL = temporaryDirectoryProvider()
            .appendingPathComponent("devjourney-mcp-\(UUID().uuidString).json", isDirectory: false)
        let config: [String: Any] = [
            "mcpServers": [
                "devjourney": [
                    "command": launcherPathProvider(),
                    "args": ["--mcp"]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL, options: .atomic)
        return configURL
    }

    private func executablePath(for client: ExternalAgentClient) -> String? {
        cliLocator().findExecutable(named: client.executableName)
    }

    private func jsonObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func isNoise(_ line: String) -> Bool {
        line.contains("WARN codex_")
            || line.contains("WARN codex_core::shell_snapshot")
            || line.contains("WARN codex_rmcp_client::rmcp_client")
    }

    private func cliLocator() -> CLIExecutableLocator {
        CLIExecutableLocator(
            fileManager: fileManager,
            environment: environmentProvider(),
            homeDirectory: NSHomeDirectory()
        )
    }
}

enum ExternalAgentRunnerError: LocalizedError {
    case clientUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .clientUnavailable(name):
            return "\(name) is not installed or not available on PATH."
        }
    }
}

private actor StreamCollector {
    private var text = ""

    func append(_ value: String) {
        text.append(value)
    }

    func contents() -> String {
        text
    }
}
