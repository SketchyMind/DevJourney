import Foundation

typealias ProviderTokenHandler = @MainActor @Sendable (String) -> Void

struct ResolvedProviderConfiguration: Sendable {
    let id: String
    let kind: AIProviderKind
    let displayName: String
    let baseURL: String?
    let defaultModel: String

    init(_ config: AIProviderConfig) {
        self.id = config.id
        self.kind = config.kindEnum
        self.displayName = config.displayName
        self.baseURL = config.baseURLEffectiveValue
        self.defaultModel = config.defaultModel
    }
}

enum AgentProviderError: LocalizedError {
    case missingAPIKey(String)
    case invalidBaseURL
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "No API key configured for \(provider)."
        case .invalidBaseURL:
            return "The configured provider base URL is invalid."
        case .invalidResponse:
            return "The provider returned an invalid response."
        case .httpError(let statusCode, let message):
            return "Provider error (\(statusCode)): \(message)"
        }
    }
}

protocol AgentProvider: Sendable {
    var kind: AIProviderKind { get }

    nonisolated func execute(
        request: AgentExecutionRequest,
        configuration: ResolvedProviderConfiguration,
        apiKey: String,
        onToken: @escaping ProviderTokenHandler
    ) async throws -> String
}

struct AgentProviderRegistry: Sendable {
    private let anthropicProvider = AnthropicProvider()
    private let openAIProvider = OpenAIProvider()
    private let compatibleProvider = OpenAICompatibleProvider()

    nonisolated func execute(
        request: AgentExecutionRequest,
        configuration: ResolvedProviderConfiguration,
        apiKey: String,
        onToken: @escaping ProviderTokenHandler
    ) async throws -> String {
        switch configuration.kind {
        case .anthropic:
            return try await anthropicProvider.execute(
                request: request,
                configuration: configuration,
                apiKey: apiKey,
                onToken: onToken
            )
        case .openAI:
            return try await openAIProvider.execute(
                request: request,
                configuration: configuration,
                apiKey: apiKey,
                onToken: onToken
            )
        case .openAICompatible:
            return try await compatibleProvider.execute(
                request: request,
                configuration: configuration,
                apiKey: apiKey,
                onToken: onToken
            )
        }
    }
}

private struct AnthropicProvider: AgentProvider {
    let kind: AIProviderKind = .anthropic

    nonisolated func execute(
        request: AgentExecutionRequest,
        configuration: ResolvedProviderConfiguration,
        apiKey: String,
        onToken: @escaping ProviderTokenHandler
    ) async throws -> String {
        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": request.model,
            "max_tokens": 4096,
            "stream": true,
            "system": request.systemPrompt,
            "messages": [
                ["role": "user", "content": request.userPrompt]
            ]
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AgentProviderError.httpError(httpResponse.statusCode, "Anthropic request failed")
        }

        var fullResponse = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            if jsonString == "[DONE]" {
                break
            }

            guard let jsonData = jsonString.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let type = event["type"] as? String
            else {
                continue
            }

            if type == "content_block_delta",
               let delta = event["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                fullResponse += text
                await onToken(text)
            }
        }

        return fullResponse
    }
}

private struct OpenAIProvider: AgentProvider {
    let kind: AIProviderKind = .openAI

    nonisolated func execute(
        request: AgentExecutionRequest,
        configuration: ResolvedProviderConfiguration,
        apiKey: String,
        onToken: @escaping ProviderTokenHandler
    ) async throws -> String {
        try await OpenAIStyleProvider.execute(
            request: request,
            baseURL: "https://api.openai.com/v1",
            apiKey: apiKey,
            onToken: onToken
        )
    }
}

private struct OpenAICompatibleProvider: AgentProvider {
    let kind: AIProviderKind = .openAICompatible

    nonisolated func execute(
        request: AgentExecutionRequest,
        configuration: ResolvedProviderConfiguration,
        apiKey: String,
        onToken: @escaping ProviderTokenHandler
    ) async throws -> String {
        guard let baseURL = configuration.baseURL else {
            throw AgentProviderError.invalidBaseURL
        }

        return try await OpenAIStyleProvider.execute(
            request: request,
            baseURL: baseURL,
            apiKey: apiKey,
            onToken: onToken
        )
    }
}

private enum OpenAIStyleProvider {
    nonisolated static func execute(
        request: AgentExecutionRequest,
        baseURL: String,
        apiKey: String,
        onToken: @escaping ProviderTokenHandler
    ) async throws -> String {
        let normalizedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalizedBaseURL.hasSuffix("/chat/completions")
            ? normalizedBaseURL
            : normalizedBaseURL + "/chat/completions") else {
            throw AgentProviderError.invalidBaseURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": request.model,
            "stream": true,
            "messages": [
                ["role": "system", "content": request.systemPrompt],
                ["role": "user", "content": request.userPrompt]
            ]
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentProviderError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AgentProviderError.httpError(httpResponse.statusCode, "OpenAI-style request failed")
        }

        var fullResponse = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" {
                break
            }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let text = delta["content"] as? String
            else {
                continue
            }

            fullResponse += text
            await onToken(text)
        }

        return fullResponse
    }
}
