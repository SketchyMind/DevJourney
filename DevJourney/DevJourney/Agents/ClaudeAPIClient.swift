import Foundation

/// Client for the Anthropic Messages API. Uses URLSession streaming.
final class ClaudeAPIClient: AIClientProtocol, Sendable {
    static let shared = ClaudeAPIClient()

    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"

    /// Returns the API key from Keychain (migrated from UserDefaults).
    private var apiKey: String {
        KeychainService.shared.readAPIKey(for: .anthropic) ?? ""
    }

    /// Send a non-streaming message and return the full text response.
    func sendMessage(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)],
        maxTokens: Int = 4096
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw ClaudeAPIError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeAPIError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw ClaudeAPIError.unexpectedFormat
        }

        return text
    }

    /// Stream a message, calling the handler for each text delta.
    func streamMessage(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)],
        maxTokens: Int = 4096,
        onDelta: @Sendable @escaping (String) -> Void
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw ClaudeAPIError.missingAPIKey
        }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": systemPrompt,
            "messages": messages.map { ["role": $0.role, "content": $0.content] }
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ClaudeAPIError.invalidResponse
        }

        var fullText = ""

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            guard jsonString != "[DONE]" else { break }

            guard let jsonData = jsonString.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            let eventType = event["type"] as? String

            if eventType == "content_block_delta",
               let delta = event["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                fullText += text
                onDelta(text)
            }
        }

        return fullText
    }
}

enum ClaudeAPIError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case unexpectedFormat

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Anthropic API key not configured. Add it in Settings."
        case .invalidResponse:
            return "Invalid response from Claude API."
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .unexpectedFormat:
            return "Unexpected response format from Claude API."
        }
    }
}
