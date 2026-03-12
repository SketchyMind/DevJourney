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
    var mobilePlatforms: [String] = []
    var planningProviderConfigId: String?
    var planningModelOverride: String = ""
    var designProviderConfigId: String?
    var designModelOverride: String = ""
    var devProviderConfigId: String?
    var devModelOverride: String = ""
    var debugProviderConfigId: String?
    var debugModelOverride: String = ""

    @Relationship(deleteRule: .cascade) var tickets: [Ticket] = []
    @Relationship(deleteRule: .cascade) var providerConfigs: [AIProviderConfig] = []

    init(
        id: String = UUID().uuidString,
        name: String,
        projectDescription: String,
        projectType: String,
        folderPath: String,
        githubRepo: String? = nil,
        githubUsername: String? = nil,
        githubAvatarURL: String? = nil,
        repoVisibility: String = "private",
        repoCreationMode: String? = nil,
        screenSizes: [String] = ["mobile", "tablet", "desktop"],
        responsiveBehavior: String = "fluid",
        techStack: String = "",
        mobilePlatforms: [String] = [],
        planningProviderConfigId: String? = nil,
        planningModelOverride: String = "",
        designProviderConfigId: String? = nil,
        designModelOverride: String = "",
        devProviderConfigId: String? = nil,
        devModelOverride: String = "",
        debugProviderConfigId: String? = nil,
        debugModelOverride: String = ""
    ) {
        self.id = id
        self.name = name
        self.projectDescription = projectDescription
        self.projectType = projectType
        self.folderPath = folderPath
        self.githubRepo = githubRepo
        self.createdAt = Date()
        self.githubUsername = githubUsername
        self.githubAvatarURL = githubAvatarURL
        self.repoVisibility = repoVisibility
        self.repoCreationMode = repoCreationMode
        self.screenSizes = screenSizes
        self.responsiveBehavior = responsiveBehavior
        self.techStack = techStack
        self.mobilePlatforms = mobilePlatforms
        self.planningProviderConfigId = planningProviderConfigId
        self.planningModelOverride = planningModelOverride
        self.designProviderConfigId = designProviderConfigId
        self.designModelOverride = designModelOverride
        self.devProviderConfigId = devProviderConfigId
        self.devModelOverride = devModelOverride
        self.debugProviderConfigId = debugProviderConfigId
        self.debugModelOverride = debugModelOverride
    }

    // MARK: - Computed Helpers

    var screenSizeEnums: [ScreenSize] {
        screenSizes.compactMap { ScreenSize(rawValue: $0) }
    }

    var responsiveBehaviorEnum: ResponsiveBehavior {
        ResponsiveBehavior(rawValue: responsiveBehavior) ?? .fluid
    }

    var mobilePlatformEnums: [MobilePlatform] {
        mobilePlatforms.compactMap { MobilePlatform(rawValue: $0) }
    }

    var normalizedMobilePlatforms: [String] {
        let validPlatforms = mobilePlatformEnums.map(\.rawValue)
        guard projectType == ProjectType.mobileApp.rawValue else { return [] }
        return validPlatforms.isEmpty
            ? [MobilePlatform.ios.rawValue, MobilePlatform.android.rawValue]
            : validPlatforms
    }

    func providerConfigId(for stage: Stage) -> String? {
        switch stage {
        case .planning:
            return planningProviderConfigId
        case .design:
            return designProviderConfigId
        case .dev:
            return devProviderConfigId
        case .debug:
            return debugProviderConfigId
        case .backlog, .complete:
            return nil
        }
    }

    func modelOverride(for stage: Stage) -> String? {
        let value: String
        switch stage {
        case .planning:
            value = planningModelOverride
        case .design:
            value = designModelOverride
        case .dev:
            value = devModelOverride
        case .debug:
            value = debugModelOverride
        case .backlog, .complete:
            value = ""
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func setProviderConfigId(_ configId: String?, for stage: Stage) {
        switch stage {
        case .planning:
            planningProviderConfigId = configId
        case .design:
            designProviderConfigId = configId
        case .dev:
            devProviderConfigId = configId
        case .debug:
            debugProviderConfigId = configId
        case .backlog, .complete:
            break
        }
    }

    func setModelOverride(_ value: String, for stage: Stage) {
        switch stage {
        case .planning:
            planningModelOverride = value
        case .design:
            designModelOverride = value
        case .dev:
            devModelOverride = value
        case .debug:
            debugModelOverride = value
        case .backlog, .complete:
            break
        }
    }
}
