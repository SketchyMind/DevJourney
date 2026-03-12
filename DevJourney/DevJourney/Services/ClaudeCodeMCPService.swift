import Foundation

struct ClaudeMCPRegistrationStatus: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case unavailable
        case notConfigured
        case configuredLocal(command: String)
        case configuredOther(description: String)
    }

    let mode: Mode

    var isReadyForLocalProjectStore: Bool {
        if case .configuredLocal = mode {
            return true
        }
        return false
    }

    var displayLabel: String {
        switch mode {
        case .unavailable:
            return "Claude Code not installed"
        case .notConfigured:
            return "Claude MCP not installed"
        case .configuredLocal:
            return "Claude MCP ready"
        case let .configuredOther(description):
            return description
        }
    }
}

struct ClaudeCodeMCPService: Sendable {
    static let shared = ClaudeCodeMCPService()

    private let fileManager: FileManager
    private let claudeUserConfigURLProvider: @Sendable () -> URL
    private let fallbackMCPConfigURLProvider: @Sendable () -> URL
    private let launcherPathProvider: @Sendable () -> String
    private let stableExecutablePathProvider: @Sendable () -> String
    private let claudePathProvider: @Sendable () async -> String?

    init(
        fileManager: FileManager = .default,
        claudeUserConfigURLProvider: @escaping @Sendable () -> URL = {
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude.json", isDirectory: false)
        },
        fallbackMCPConfigURLProvider: @escaping @Sendable () -> URL = {
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/.mcp.json", isDirectory: false)
        },
        launcherPathProvider: @escaping @Sendable () -> String = {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            return root
                .appendingPathComponent("DevJourney", isDirectory: true)
                .appendingPathComponent("devjourney-mcp", isDirectory: false)
                .path
        },
        stableExecutablePathProvider: @escaping @Sendable () -> String = {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            return root
                .appendingPathComponent("DevJourney", isDirectory: true)
                .appendingPathComponent("MCP", isDirectory: true)
                .appendingPathComponent("DevJourney.app", isDirectory: true)
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent("DevJourney", isDirectory: false)
                .path
        },
        claudePathProvider: @escaping @Sendable () async -> String? = {
            await MainActor.run {
                CLIExecutableLocator().findExecutable(named: "claude")
            }
        }
    ) {
        self.fileManager = fileManager
        self.claudeUserConfigURLProvider = claudeUserConfigURLProvider
        self.fallbackMCPConfigURLProvider = fallbackMCPConfigURLProvider
        self.launcherPathProvider = launcherPathProvider
        self.stableExecutablePathProvider = stableExecutablePathProvider
        self.claudePathProvider = claudePathProvider
    }

    func loadStatus() async -> ClaudeMCPRegistrationStatus {
        guard await claudePathProvider() != nil else {
            return ClaudeMCPRegistrationStatus(mode: .unavailable)
        }

        let configCandidates = [claudeUserConfigURLProvider(), fallbackMCPConfigURLProvider()]
        for url in configCandidates where fileManager.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let mcpServers = json["mcpServers"] as? [String: Any],
                  let devJourney = mcpServers["devjourney"] as? [String: Any] else {
                continue
            }

            if let type = devJourney["type"] as? String,
               type == "http",
               devJourney["url"] as? String != nil {
                return ClaudeMCPRegistrationStatus(mode: .configuredOther(description: "Claude MCP uses HTTP"))
            }

            let command = (devJourney["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !command.isEmpty {
                if isLocalDevJourneyCommand(command) {
                    return ClaudeMCPRegistrationStatus(mode: .configuredLocal(command: command))
                }
                return ClaudeMCPRegistrationStatus(mode: .configuredOther(description: "Claude MCP uses another command"))
            }
        }

        return ClaudeMCPRegistrationStatus(mode: .notConfigured)
    }

    private func isLocalDevJourneyCommand(_ command: String) -> Bool {
        let launcherPath = launcherPathProvider()
        let executablePath = stableExecutablePathProvider()
        return command == launcherPath || command == executablePath
    }
}
