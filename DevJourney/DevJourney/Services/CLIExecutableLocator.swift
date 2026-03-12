import Foundation

struct CLIExecutableLocator {
    private let fileManager: FileManager
    private let environment: [String: String]
    private let homeDirectory: String

    init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) {
        self.fileManager = fileManager
        self.environment = environment
        self.homeDirectory = homeDirectory
    }

    func findExecutable(named name: String) -> String? {
        for directory in searchDirectories() {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(name, isDirectory: false)
                .path
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    func augmentedEnvironment() -> [String: String] {
        var updated = environment
        updated["PATH"] = searchDirectories().joined(separator: ":")
        return updated
    }

    private func searchDirectories() -> [String] {
        var directories: [String] = []

        if let path = environment["PATH"] {
            directories.append(contentsOf: path.split(separator: ":").map(String.init))
        }

        directories.append(contentsOf: [
            "\(homeDirectory)/.local/bin",
            "\(homeDirectory)/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/opt/pmk/env/global/bin"
        ])

        var seen = Set<String>()
        return directories.compactMap { directory in
            let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let standardized = URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL.path
            guard seen.insert(standardized).inserted else { return nil }
            return standardized
        }
    }
}
