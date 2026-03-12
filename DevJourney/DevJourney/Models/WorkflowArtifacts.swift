import Foundation
import SwiftData

enum TicketHandoverState: String, Codable, CaseIterable, Sendable {
    case idle = "Idle"
    case running = "Running"
    case readyForReview = "Ready for Review"
    case blocked = "Blocked"
    case handedOff = "Handed Off"
    case returned = "Returned"
    case complete = "Complete"

    var displayName: String { rawValue }
}

enum BuildStatus: String, Codable, CaseIterable, Sendable {
    case notRun = "Not Run"
    case pending = "Pending"
    case passed = "Passed"
    case failed = "Failed"

    var displayName: String { rawValue }
}

enum ReleaseRecommendation: String, Codable, CaseIterable, Sendable {
    case pending = "Pending"
    case ready = "Ready"
    case blocked = "Blocked"

    var displayName: String { rawValue }
}

struct AgentExecutionRequest: Codable, Sendable {
    let ticketId: String
    let stage: String
    let providerId: String
    let model: String
    let systemPrompt: String
    let userPrompt: String
    let toolPolicy: String
}

enum AgentExecutionEventType: String, Codable, CaseIterable, Sendable {
    case started
    case tokenDelta
    case thoughtDelta
    case toolCall
    case artifactPatched
    case clarificationRequested
    case completed
    case failed
}

struct AgentExecutionEvent: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let type: AgentExecutionEventType
    let message: String
    let metadata: [String: String]
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        type: AgentExecutionEventType,
        message: String,
        metadata: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.message = message
        self.metadata = metadata
        self.createdAt = createdAt
    }
}

struct HandoverGateResult: Codable, Sendable {
    let stage: String
    let passed: Bool
    let missingFields: [String]
    let blockingQuestions: [String]
    let score: Double
}

typealias ClarificationThread = ClarificationItem
typealias ReviewDecision = ReviewResult

@Model
final class PlanningSpec {
    @Attribute(.unique) var id: String
    var ticketId: String
    var problem: String
    var scopeIn: [String]
    var scopeOut: [String]
    var acceptanceCriteria: [String]
    var dependencies: [String]
    var assumptions: [String]
    var risks: [String]
    var subtasks: [String]
    var definitionOfReady: [String]
    var summary: [String]
    var planningScore: Double
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        ticketId: String,
        problem: String = "",
        scopeIn: [String] = [],
        scopeOut: [String] = [],
        acceptanceCriteria: [String] = [],
        dependencies: [String] = [],
        assumptions: [String] = [],
        risks: [String] = [],
        subtasks: [String] = [],
        definitionOfReady: [String] = [],
        summary: [String] = [],
        planningScore: Double = 0
    ) {
        self.id = id
        self.ticketId = ticketId
        self.problem = problem
        self.scopeIn = scopeIn
        self.scopeOut = scopeOut
        self.acceptanceCriteria = acceptanceCriteria
        self.dependencies = dependencies
        self.assumptions = assumptions
        self.risks = risks
        self.subtasks = subtasks
        self.definitionOfReady = definitionOfReady
        self.summary = summary
        self.planningScore = planningScore
        self.updatedAt = Date()
    }
}

@Model
final class DesignSpec {
    @Attribute(.unique) var id: String
    var ticketId: String
    var appPlacement: String
    var affectedScreens: [String]
    var userFlow: [String]
    var components: [String]
    var microcopy: [String]
    var statesMatrix: [String]
    var responsiveRules: [String]
    var accessibilityNotes: [String]
    var figmaRefs: [String]
    var summary: [String]
    var designScore: Double
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        ticketId: String,
        appPlacement: String = "",
        affectedScreens: [String] = [],
        userFlow: [String] = [],
        components: [String] = [],
        microcopy: [String] = [],
        statesMatrix: [String] = [],
        responsiveRules: [String] = [],
        accessibilityNotes: [String] = [],
        figmaRefs: [String] = [],
        summary: [String] = [],
        designScore: Double = 0
    ) {
        self.id = id
        self.ticketId = ticketId
        self.appPlacement = appPlacement
        self.affectedScreens = affectedScreens
        self.userFlow = userFlow
        self.components = components
        self.microcopy = microcopy
        self.statesMatrix = statesMatrix
        self.responsiveRules = responsiveRules
        self.accessibilityNotes = accessibilityNotes
        self.figmaRefs = figmaRefs
        self.summary = summary
        self.designScore = designScore
        self.updatedAt = Date()
    }
}

@Model
final class DevExecution {
    @Attribute(.unique) var id: String
    var ticketId: String
    var branch: String
    var commitList: [String]
    var changedFiles: [FileChange]
    var previewURLs: [String]
    var implementationNotes: [String]
    var buildStatus: String
    var summary: [String]
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        ticketId: String,
        branch: String = "",
        commitList: [String] = [],
        changedFiles: [FileChange] = [],
        previewURLs: [String] = [],
        implementationNotes: [String] = [],
        buildStatus: BuildStatus = .notRun,
        summary: [String] = []
    ) {
        self.id = id
        self.ticketId = ticketId
        self.branch = branch
        self.commitList = commitList
        self.changedFiles = changedFiles
        self.previewURLs = previewURLs
        self.implementationNotes = implementationNotes
        self.buildStatus = buildStatus.rawValue
        self.summary = summary
        self.updatedAt = Date()
    }

    var buildStatusEnum: BuildStatus {
        BuildStatus(rawValue: buildStatus) ?? .notRun
    }
}

@Model
final class DebugReport {
    @Attribute(.unique) var id: String
    var ticketId: String
    var testedScenarios: [String]
    var failedScenarios: [String]
    var bugItems: [String]
    var severitySummary: String
    var releaseRecommendation: String
    var summary: [String]
    var coverageScore: Double
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        ticketId: String,
        testedScenarios: [String] = [],
        failedScenarios: [String] = [],
        bugItems: [String] = [],
        severitySummary: String = "",
        releaseRecommendation: ReleaseRecommendation = .pending,
        summary: [String] = [],
        coverageScore: Double = 0
    ) {
        self.id = id
        self.ticketId = ticketId
        self.testedScenarios = testedScenarios
        self.failedScenarios = failedScenarios
        self.bugItems = bugItems
        self.severitySummary = severitySummary
        self.releaseRecommendation = releaseRecommendation.rawValue
        self.summary = summary
        self.coverageScore = coverageScore
        self.updatedAt = Date()
    }

    var releaseRecommendationEnum: ReleaseRecommendation {
        ReleaseRecommendation(rawValue: releaseRecommendation) ?? .pending
    }
}
