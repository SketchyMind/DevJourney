import Foundation
import AppKit

class FileService {

    @MainActor
    func selectFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a project folder"

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func readProjectFiles(at url: URL) -> [String: String] {
        var result: [String: String] = [:]
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return result
        }

        let textExtensions: Set<String> = [
            "swift", "py", "js", "ts", "jsx", "tsx", "json", "yaml", "yml",
            "md", "txt", "html", "css", "scss", "xml", "toml", "rs", "go",
            "java", "kt", "c", "cpp", "h", "hpp", "rb", "sh", "zsh",
            "gitignore", "env.example", "Dockerfile", "Makefile"
        ]

        let maxFileSize: UInt64 = 512 * 1024 // 512 KB

        for case let fileURL as URL in enumerator {
            let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")

            // Skip common non-source directories
            if relativePath.hasPrefix("node_modules/") ||
               relativePath.hasPrefix(".build/") ||
               relativePath.hasPrefix("build/") ||
               relativePath.hasPrefix("DerivedData/") ||
               relativePath.hasPrefix(".git/") ||
               relativePath.hasPrefix("Pods/") {
                continue
            }

            let ext = fileURL.pathExtension.lowercased()
            guard textExtensions.contains(ext) || fileURL.lastPathComponent.contains(".") == false else {
                continue
            }

            do {
                let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
                let fileSize = attrs[.size] as? UInt64 ?? 0
                guard fileSize <= maxFileSize else { continue }

                let content = try String(contentsOf: fileURL, encoding: .utf8)
                result[relativePath] = content
            } catch {
                continue
            }
        }

        return result
    }

    func getGitRemote(at url: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", url.path, "config", "--get", "remote.origin.url"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func listFiles(at url: URL) -> [String] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents.map { $0.lastPathComponent }
    }
}
