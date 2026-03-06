import Foundation
import SwiftData

@Model
final class Project {
    @Attribute(.unique) var id: String
    var name: String
    var projectDescription: String
    var projectType: String
    var folderPath: String
    var githubRepo: String?
    var defaultModel: String = "claude-sonnet-4-5-20251001"
    var createdAt: Date

    // GitHub Connection
    var githubUsername: String?
    var githubAvatarURL: String?
    var repoVisibility: String = "private"
    var repoCreationMode: String?

    // Project Settings
    var screenSizes: [String] = ["mobile", "tablet", "desktop"]
    var responsiveBehavior: String = "fluid"
    var techStack: String = ""

    // AI Provider
    var defaultProvider: String = "anthropic"

    @Relationship(deleteRule: .cascade) var tickets: [Ticket] = []

    init(
        id: String = UUID().uuidString,
        name: String,
        projectDescription: String,
        projectType: String,
        folderPath: String,
        githubRepo: String? = nil,
        defaultModel: String = "claude-sonnet-4-5-20251001",
        githubUsername: String? = nil,
        githubAvatarURL: String? = nil,
        repoVisibility: String = "private",
        repoCreationMode: String? = nil,
        screenSizes: [String] = ["mobile", "tablet", "desktop"],
        responsiveBehavior: String = "fluid",
        techStack: String = "",
        defaultProvider: String = "anthropic"
    ) {
        self.id = id
        self.name = name
        self.projectDescription = projectDescription
        self.projectType = projectType
        self.folderPath = folderPath
        self.githubRepo = githubRepo
        self.defaultModel = defaultModel
        self.createdAt = Date()
        self.githubUsername = githubUsername
        self.githubAvatarURL = githubAvatarURL
        self.repoVisibility = repoVisibility
        self.repoCreationMode = repoCreationMode
        self.screenSizes = screenSizes
        self.responsiveBehavior = responsiveBehavior
        self.techStack = techStack
        self.defaultProvider = defaultProvider
    }

    // MARK: - Computed Helpers

    var screenSizeEnums: [ScreenSize] {
        screenSizes.compactMap { ScreenSize(rawValue: $0) }
    }

    var responsiveBehaviorEnum: ResponsiveBehavior {
        ResponsiveBehavior(rawValue: responsiveBehavior) ?? .fluid
    }

    var defaultProviderEnum: AIProvider {
        AIProvider(rawValue: defaultProvider) ?? .anthropic
    }
}
