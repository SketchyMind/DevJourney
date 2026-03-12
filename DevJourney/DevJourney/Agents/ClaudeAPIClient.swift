import Foundation

/// Anthropic Messages API client for running stage agents.
/// Streams responses and updates the AgentSession in real time.
@MainActor
final class ClaudeAPIClient {
    static let keychainService = "com.devjourney.anthropic.apikey"

    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"
    private let defaultModel = "claude-sonnet-4-20250514"

    /// Save API key to Keychain
    static func saveAPIKey(_ key: String) {
        try? KeychainService.shared.saveString(
            service: keychainService,
            account: "default",
            value: key
        )
    }

    /// Read API key from Keychain
    static func readAPIKey() -> String? {
        KeychainService.shared.readString(
            service: keychainService,
            account: "default"
        )
    }

    /// Delete API key from Keychain
    static func deleteAPIKey() {
        try? KeychainService.shared.delete(
            service: keychainService,
            account: "default"
        )
    }

    /// Check if API key is configured
    static var isConfigured: Bool {
        readAPIKey() != nil
    }

    /// Run a stage agent for a ticket, streaming results into the session.
    func runAgent(
        systemPrompt: String,
        userMessage: String,
        session: AgentSession,
        onUpdate: @escaping () -> Void
    ) async throws {
        guard let apiKey = Self.readAPIKey() else {
            throw ClaudeAPIError.noAPIKey
        }

        session.addThought("Starting \(session.stage) agent...")
        onUpdate()

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": defaultModel,
            "max_tokens": 4096,
            "stream": true,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        session.addDialogEntry(role: "user", content: userMessage)
        onUpdate()

        // Stream the response
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw ClaudeAPIError.invalidAPIKey
        }

        guard httpResponse.statusCode == 200 else {
            throw ClaudeAPIError.httpError(httpResponse.statusCode)
        }

        var fullResponse = ""

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            guard jsonString != "[DONE]" else { break }

            guard let data = jsonString.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String
            else { continue }

            switch type {
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    fullResponse += text
                }

            case "message_stop":
                break

            default:
                break
            }
        }

        // Parse the response into thoughts, summary, etc.
        let result = parseAgentResponse(fullResponse)

        for thought in result.thoughts {
            session.addThought(thought)
        }
        session.resultSummary = result.summary
        session.filesChanged = result.filesChanged

        session.addDialogEntry(role: "assistant", content: fullResponse)
        onUpdate()

        if result.needsClarification {
            session.addThought("Agent needs clarification — check the response for questions.")
        }

        session.addThought("Agent completed.")
        onUpdate()
    }

    // MARK: - Response Parsing

    private func parseAgentResponse(_ response: String) -> AgentResponseResult {
        var result = AgentResponseResult()
        var currentSection = ""

        for line in response.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("### Thoughts") {
                currentSection = "thoughts"
            } else if trimmed.hasPrefix("### Summary") {
                currentSection = "summary"
            } else if trimmed.hasPrefix("### Clarification") {
                currentSection = "clarification"
                result.needsClarification = true
            } else if trimmed.hasPrefix("### Files") {
                currentSection = "files"
            } else if trimmed.hasPrefix("- ") {
                let content = String(trimmed.dropFirst(2))
                switch currentSection {
                case "thoughts":
                    result.thoughts.append(content)
                case "summary":
                    result.summary.append(content)
                case "clarification":
                    result.clarificationQuestion = content
                case "files":
                    if let change = parseFileChange(content) {
                        result.filesChanged.append(change)
                    }
                default:
                    break
                }
            }
        }

        // If no structured sections found, treat entire response as summary
        if result.thoughts.isEmpty && result.summary.isEmpty {
            result.summary = [response]
        }

        return result
    }

    private func parseFileChange(_ line: String) -> FileChange? {
        // Expected format: "path/to/file.swift (created, +10, -0)"
        let parts = line.components(separatedBy: " (")
        guard parts.count == 2 else { return nil }
        let path = parts[0]
        let meta = parts[1].replacingOccurrences(of: ")", with: "")
        let metaParts = meta.components(separatedBy: ", ")
        let status = metaParts.first ?? "modified"
        return FileChange(path: path, status: status, additions: 0, deletions: 0)
    }
}

// MARK: - Errors

enum ClaudeAPIError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Anthropic API key configured. Add one in Settings."
        case .invalidAPIKey:
            return "Invalid API key. Check your key in Settings."
        case .invalidResponse:
            return "Invalid response from Anthropic API."
        case .httpError(let code):
            return "API error (HTTP \(code))."
        }
    }
}
