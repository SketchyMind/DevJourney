import Foundation

struct MCPConnectionStatusSnapshot: Codable, Equatable, Sendable {
    var clientName: String?
    var lastSeenAt: Date?
    var serverPID: Int32?

    static let disconnected = MCPConnectionStatusSnapshot(
        clientName: nil,
        lastSeenAt: nil,
        serverPID: nil
    )

    func isClientConnected(now: Date = Date(), timeout: TimeInterval = 15) -> Bool {
        guard let clientName = clientName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !clientName.isEmpty,
              let lastSeenAt else {
            return false
        }
        return now.timeIntervalSince(lastSeenAt) <= timeout
    }

    var displayClientName: String {
        let trimmed = clientName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "MCP client" : trimmed
    }
}

struct MCPConnectionStatusStore: Sendable {
    static let shared = MCPConnectionStatusStore()

    private let fileManager: FileManager
    private let rootDirectoryProvider: @Sendable () -> URL

    init(
        fileManager: FileManager = .default,
        rootDirectoryProvider: @escaping @Sendable () -> URL = {
            let appSupportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            return appSupportRoot.appendingPathComponent("DevJourney", isDirectory: true)
        }
    ) {
        self.fileManager = fileManager
        self.rootDirectoryProvider = rootDirectoryProvider
    }

    func load() -> MCPConnectionStatusSnapshot {
        let url = statusFileURL()
        guard let data = try? Data(contentsOf: url) else {
            return .disconnected
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(MCPConnectionStatusSnapshot.self, from: data)) ?? .disconnected
    }

    func write(clientName: String?) throws {
        try fileManager.createDirectory(at: rootDirectoryProvider(), withIntermediateDirectories: true)

        let snapshot = MCPConnectionStatusSnapshot(
            clientName: clientName,
            lastSeenAt: Date(),
            serverPID: ProcessInfo.processInfo.processIdentifier
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: statusFileURL(), options: .atomic)
    }

    func clear() {
        let url = statusFileURL()
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func statusFileURL() -> URL {
        rootDirectoryProvider().appendingPathComponent("mcp-connection.json", isDirectory: false)
    }
}
