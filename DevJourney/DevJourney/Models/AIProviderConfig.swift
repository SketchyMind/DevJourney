import Foundation
import SwiftData

enum AIProviderKind: String, Codable, CaseIterable, Sendable {
    case anthropic
    case openAI
    case openAICompatible

    var displayName: String {
        switch self {
        case .anthropic:
            return "Anthropic"
        case .openAI:
            return "OpenAI"
        case .openAICompatible:
            return "OpenAI-Compatible"
        }
    }

    var iconName: String {
        switch self {
        case .anthropic:
            return "brain.head.profile"
        case .openAI:
            return "sparkles"
        case .openAICompatible:
            return "network"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic:
            return "claude-sonnet-4-20250514"
        case .openAI:
            return "gpt-4.1"
        case .openAICompatible:
            return "gpt-4o-mini"
        }
    }

    var defaultBaseURL: String? {
        switch self {
        case .anthropic:
            return nil
        case .openAI:
            return nil
        case .openAICompatible:
            return "https://api.openai.com/v1"
        }
    }

    var supportsCustomBaseURL: Bool {
        self == .openAICompatible
    }
}

@Model
final class AIProviderConfig {
    @Attribute(.unique) var id: String
    var projectId: String
    var kind: String
    var displayName: String
    var baseURL: String?
    var apiKeyReference: String
    var defaultModel: String
    var enabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        projectId: String,
        kind: AIProviderKind,
        displayName: String? = nil,
        baseURL: String? = nil,
        apiKeyReference: String? = nil,
        defaultModel: String? = nil,
        enabled: Bool = true
    ) {
        self.id = id
        self.projectId = projectId
        self.kind = kind.rawValue
        self.displayName = displayName ?? kind.displayName
        self.baseURL = baseURL ?? kind.defaultBaseURL
        self.apiKeyReference = apiKeyReference ?? id
        self.defaultModel = defaultModel ?? kind.defaultModel
        self.enabled = enabled
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var kindEnum: AIProviderKind {
        AIProviderKind(rawValue: kind) ?? .anthropic
    }

    var baseURLEffectiveValue: String? {
        let trimmed = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? kindEnum.defaultBaseURL : trimmed
    }

    func touch() {
        updatedAt = Date()
    }
}
