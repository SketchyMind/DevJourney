import Foundation

protocol AIClientProtocol: Sendable {
    func sendMessage(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)],
        maxTokens: Int
    ) async throws -> String

    func streamMessage(
        model: String,
        systemPrompt: String,
        messages: [(role: String, content: String)],
        maxTokens: Int,
        onDelta: @Sendable @escaping (String) -> Void
    ) async throws -> String
}

enum AIClientError: LocalizedError {
    case missingAPIKey(AIProvider)
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case unexpectedFormat

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let p): return "\(p.displayName) API key not configured."
        case .invalidResponse: return "Invalid response from AI API."
        case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
        case .unexpectedFormat: return "Unexpected response format."
        }
    }
}

struct AIModelConfig: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let provider: AIProvider
    let displayName: String
    let contextWindow: Int
    let maxOutputTokens: Int

    static let allModels: [AIModelConfig] = [
        // Anthropic
        .init(id: "claude-opus-4-6", provider: .anthropic, displayName: "Claude Opus 4.6", contextWindow: 200_000, maxOutputTokens: 32_768),
        .init(id: "claude-sonnet-4-5-20251001", provider: .anthropic, displayName: "Claude Sonnet 4.5", contextWindow: 200_000, maxOutputTokens: 16_384),
        .init(id: "claude-haiku-4-5-20251001", provider: .anthropic, displayName: "Claude Haiku 4.5", contextWindow: 200_000, maxOutputTokens: 8_192),
        // OpenAI
        .init(id: "gpt-4o", provider: .openai, displayName: "GPT-4o", contextWindow: 128_000, maxOutputTokens: 16_384),
        .init(id: "gpt-4o-mini", provider: .openai, displayName: "GPT-4o Mini", contextWindow: 128_000, maxOutputTokens: 16_384),
        // Gemini
        .init(id: "gemini-2.5-pro-preview-06-05", provider: .gemini, displayName: "Gemini 2.5 Pro", contextWindow: 1_048_576, maxOutputTokens: 65_536),
        .init(id: "gemini-2.0-flash", provider: .gemini, displayName: "Gemini 2.0 Flash", contextWindow: 1_048_576, maxOutputTokens: 8_192),
    ]

    static func config(for modelId: String) -> AIModelConfig? {
        allModels.first { $0.id == modelId }
    }

    static var configuredModels: [AIModelConfig] {
        allModels.filter { KeychainService.shared.isProviderConnected($0.provider) }
    }
}

enum AIClientFactory {
    static func client(for modelId: String) -> any AIClientProtocol {
        // Currently all models route through the Anthropic client.
        // OpenAI and Gemini clients will be added as separate implementations.
        return ClaudeAPIClient.shared
    }

    static func maxTokens(for modelId: String, requested: Int = 4096) -> Int {
        guard let config = AIModelConfig.config(for: modelId) else { return requested }
        return min(requested, config.maxOutputTokens)
    }
}
