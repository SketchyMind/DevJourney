import Foundation

@MainActor
struct MCPLaunchService {
    static let shared = MCPLaunchService()

    private let fileManager: FileManager
    private let rootDirectoryProvider: () -> URL
    private let sourceBundleURLProvider: () -> URL
    private let executablePathProvider: () -> String?

    init(
        fileManager: FileManager = .default,
        rootDirectoryProvider: @escaping () -> URL = {
            let appSupportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
            return appSupportRoot.appendingPathComponent("DevJourney", isDirectory: true)
        },
        sourceBundleURLProvider: @escaping () -> URL = { Bundle.main.bundleURL },
        executablePathProvider: @escaping () -> String? = { Bundle.main.executablePath }
    ) {
        self.fileManager = fileManager
        self.rootDirectoryProvider = rootDirectoryProvider
        self.sourceBundleURLProvider = sourceBundleURLProvider
        self.executablePathProvider = executablePathProvider
    }

    func stableCommandPath() -> String {
        (try? prepareStableCommand()) ?? executablePathProvider() ?? "/path/to/DevJourney.app/Contents/MacOS/DevJourney"
    }

    @discardableResult
    func prepareStableCommand() throws -> String {
        let stableExecutablePath = try prepareStableExecutablePath()
        let scriptURL = launcherScriptURL()
        try fileManager.createDirectory(
            at: scriptURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let scriptContents = """
        #!/bin/sh
        exec \(shellQuoted(stableExecutablePath)) "$@"
        """

        let normalizedScript = scriptContents + "\n"
        if let existing = try? String(contentsOf: scriptURL, encoding: .utf8), existing != normalizedScript {
            try normalizedScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        } else if !fileManager.fileExists(atPath: scriptURL.path) {
            try normalizedScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        }

        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        return scriptURL.path
    }

    @discardableResult
    func refreshLauncher() throws -> String {
        try prepareStableCommand()
    }

    @discardableResult
    func prepareStableExecutablePath() throws -> String {
        guard let executablePath = executablePathProvider(),
              !executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MCPLaunchError.missingExecutablePath
        }

        let sourceBundleURL = sourceBundleURLProvider().standardizedFileURL
        guard sourceBundleURL.pathExtension == "app" else {
            throw MCPLaunchError.missingAppBundle
        }

        let stableBundleURL = installedBundleURL().standardizedFileURL
        if stableBundleURL != sourceBundleURL {
            try installStableBundleIfNeeded(from: sourceBundleURL, executablePath: executablePath, to: stableBundleURL)
        }

        let stableExecutableURL = stableBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(URL(fileURLWithPath: executablePath).lastPathComponent, isDirectory: false)

        guard fileManager.fileExists(atPath: stableExecutableURL.path) else {
            throw MCPLaunchError.missingInstalledExecutable
        }
        return stableExecutableURL.path
    }

    private func installStableBundleIfNeeded(from sourceBundleURL: URL, executablePath: String, to targetBundleURL: URL) throws {
        let sourceExecutableURL = URL(fileURLWithPath: executablePath)
        let targetExecutableURL = targetBundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(sourceExecutableURL.lastPathComponent, isDirectory: false)

        if fileManager.fileExists(atPath: targetExecutableURL.path),
           try bundleExecutableMatches(source: sourceExecutableURL, target: targetExecutableURL) {
            return
        }

        try fileManager.createDirectory(
            at: targetBundleURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: targetBundleURL.path) {
            try fileManager.removeItem(at: targetBundleURL)
        }
        try fileManager.copyItem(at: sourceBundleURL, to: targetBundleURL)
    }

    private func bundleExecutableMatches(source: URL, target: URL) throws -> Bool {
        let sourceAttributes = try fileManager.attributesOfItem(atPath: source.path)
        let targetAttributes = try fileManager.attributesOfItem(atPath: target.path)

        let sourceSize = sourceAttributes[.size] as? NSNumber
        let targetSize = targetAttributes[.size] as? NSNumber
        let sourceDate = sourceAttributes[.modificationDate] as? Date
        let targetDate = targetAttributes[.modificationDate] as? Date

        return sourceSize == targetSize && sourceDate == targetDate
    }

    private func launcherScriptURL() -> URL {
        rootDirectoryProvider().appendingPathComponent("devjourney-mcp", isDirectory: false)
    }

    private func installedBundleURL() -> URL {
        rootDirectoryProvider()
            .appendingPathComponent("MCP", isDirectory: true)
            .appendingPathComponent("DevJourney.app", isDirectory: true)
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

enum MCPLaunchError: LocalizedError {
    case missingExecutablePath
    case missingAppBundle
    case missingInstalledExecutable

    var errorDescription: String? {
        switch self {
        case .missingExecutablePath:
            return "Could not determine the DevJourney executable path."
        case .missingAppBundle:
            return "Could not determine the DevJourney app bundle."
        case .missingInstalledExecutable:
            return "Could not prepare the stable MCP executable."
        }
    }
}
