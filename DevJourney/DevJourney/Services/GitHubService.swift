import Foundation

struct RepositoryInfo {
    let name: String
    let remotePath: String
    let currentBranch: String
    let lastCommitMessage: String
    let lastCommitDate: Date?
}

struct CommitResult {
    let success: Bool
    let commitHash: String?
    let message: String
}

final class GitHubService: Sendable {

    func cloneRepository(url: String, to destination: URL) async -> Result<URL, Error> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["clone", url, destination.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                return .success(destination)
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                return .failure(GitError.cloneFailed(output))
            }
        } catch {
            return .failure(error)
        }
    }

    func getRepositoryInfo(path: URL) async -> RepositoryInfo? {
        let name = await runGitAsync(at: path, args: ["rev-parse", "--show-toplevel"])
            .flatMap { URL(fileURLWithPath: $0).lastPathComponent } ?? path.lastPathComponent

        let remote = await runGitAsync(at: path, args: ["config", "--get", "remote.origin.url"]) ?? ""
        let branch = await runGitAsync(at: path, args: ["rev-parse", "--abbrev-ref", "HEAD"]) ?? "main"
        let commitMsg = await runGitAsync(at: path, args: ["log", "-1", "--pretty=%s"]) ?? ""
        let commitDateStr = await runGitAsync(at: path, args: ["log", "-1", "--pretty=%aI"])

        var commitDate: Date?
        if let dateStr = commitDateStr {
            let formatter = ISO8601DateFormatter()
            commitDate = formatter.date(from: dateStr)
        }

        return RepositoryInfo(
            name: name,
            remotePath: remote,
            currentBranch: branch,
            lastCommitMessage: commitMsg,
            lastCommitDate: commitDate
        )
    }

    func createCommit(path: URL, message: String, files: [String]) async -> CommitResult {
        for file in files {
            _ = await runGitAsync(at: path, args: ["add", file])
        }

        guard let _ = await runGitAsync(at: path, args: ["commit", "-m", message]) else {
            return CommitResult(success: false, commitHash: nil, message: "Commit failed")
        }

        let hash = await runGitAsync(at: path, args: ["rev-parse", "--short", "HEAD"])
        return CommitResult(success: true, commitHash: hash, message: message)
    }

    func readFile(repoPath: URL, filePath: String) -> String? {
        let fullPath = repoPath.appendingPathComponent(filePath)
        return try? String(contentsOf: fullPath, encoding: .utf8)
    }

    // MARK: - Private

    private func runGit(at path: URL, args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path.path] + args
        process.currentDirectoryURL = path

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""
                print("[git \(args.joined(separator: " "))] failed: \(errStr)")
                return nil
            }

            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("[git \(args.joined(separator: " "))] exception: \(error)")
            return nil
        }
    }

    /// Non-blocking version that runs git on a background thread.
    func runGitAsync(at path: URL, args: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.runGit(at: path, args: args)
                continuation.resume(returning: result)
            }
        }
    }
}

enum GitError: LocalizedError {
    case cloneFailed(String)
    case notARepository
    case apiFailed(String)

    var errorDescription: String? {
        switch self {
        case .cloneFailed(let msg): return "Clone failed: \(msg)"
        case .notARepository: return "Not a git repository"
        case .apiFailed(let msg): return "GitHub API error: \(msg)"
        }
    }
}

// MARK: - GitHub API Models

struct GitHubCreateRepoRequest: Codable, Sendable {
    let name: String
    let description: String
    let `private`: Bool
    let autoInit: Bool

    enum CodingKeys: String, CodingKey {
        case name, description
        case `private` = "private"
        case autoInit = "auto_init"
    }
}

struct GitHubRepoResponse: Codable, Sendable {
    let id: Int
    let fullName: String
    let htmlUrl: String
    let cloneUrl: String
    let sshUrl: String
    let `private`: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case htmlUrl = "html_url"
        case cloneUrl = "clone_url"
        case sshUrl = "ssh_url"
        case `private` = "private"
    }
}

struct GitHubUserResponse: Codable, Sendable {
    let login: String
    let avatarUrl: String

    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
    }
}

// MARK: - GitHub API Methods

extension GitHubService {
    private static let apiBase = "https://api.github.com"

    func fetchAuthenticatedUser(token: String) async throws -> GitHubUserResponse {
        var request = URLRequest(url: URL(string: "\(Self.apiBase)/user")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitError.apiFailed("Failed to fetch user info")
        }
        return try JSONDecoder().decode(GitHubUserResponse.self, from: data)
    }

    func createRepository(request body: GitHubCreateRepoRequest, token: String) async throws -> GitHubRepoResponse {
        var request = URLRequest(url: URL(string: "\(Self.apiBase)/user/repos")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitError.apiFailed("Invalid response")
        }
        guard http.statusCode == 201 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitError.apiFailed("Create repo failed (\(http.statusCode)): \(errorBody)")
        }
        return try JSONDecoder().decode(GitHubRepoResponse.self, from: data)
    }

    func verifyRepository(owner: String, repo: String, token: String) async throws -> GitHubRepoResponse {
        var request = URLRequest(url: URL(string: "\(Self.apiBase)/repos/\(owner)/\(repo)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitError.apiFailed("Repository not found or access denied")
        }
        return try JSONDecoder().decode(GitHubRepoResponse.self, from: data)
    }
}
