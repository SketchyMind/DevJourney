import Foundation
import SwiftData

@Model
final class Ticket {
    @Attribute(.unique) var id: String
    var title: String
    var ticketDescription: String
    var priority: String = Priority.medium.rawValue
    var tags: [String] = []
    var stage: String = Stage.backlog.rawValue
    var status: String = TicketStatus.inactive.rawValue
    var handoverState: String = TicketHandoverState.idle.rawValue
    var blockedReason: String?
    var activeProviderConfigId: String?
    var activeModel: String?
    var agentCount: Int = 1
    var createdAt: Date
    var updatedAt: Date

    // Relationships
    var projectId: String

    @Relationship(deleteRule: .cascade) var sessions: [AgentSession] = []
    @Relationship(deleteRule: .cascade) var clarifications: [ClarificationItem] = []
    @Relationship(deleteRule: .cascade) var reviewResults: [ReviewResult] = []
    @Relationship(deleteRule: .cascade) var planningSpecs: [PlanningSpec] = []
    @Relationship(deleteRule: .cascade) var designSpecs: [DesignSpec] = []
    @Relationship(deleteRule: .cascade) var devExecutions: [DevExecution] = []
    @Relationship(deleteRule: .cascade) var debugReports: [DebugReport] = []

    init(
        id: String = UUID().uuidString,
        title: String,
        ticketDescription: String,
        priority: Priority = .medium,
        projectId: String
    ) {
        self.id = id
        self.title = title
        self.ticketDescription = ticketDescription
        self.priority = priority.rawValue
        self.projectId = projectId
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var stageEnum: Stage {
        Stage(rawValue: stage) ?? .backlog
    }

    var statusEnum: TicketStatus {
        TicketStatus(rawValue: status) ?? .inactive
    }

    var priorityEnum: Priority {
        Priority(rawValue: priority) ?? .medium
    }

    var handoverStateEnum: TicketHandoverState {
        TicketHandoverState(rawValue: handoverState) ?? .idle
    }

    var pendingClarificationCount: Int {
        clarifications.filter { $0.answer == nil }.count
    }

    var latestPlanningSpec: PlanningSpec? {
        planningSpecs.max { $0.updatedAt < $1.updatedAt }
    }

    var latestDesignSpec: DesignSpec? {
        designSpecs.max { $0.updatedAt < $1.updatedAt }
    }

    var latestDevExecution: DevExecution? {
        devExecutions.max { $0.updatedAt < $1.updatedAt }
    }

    var latestDebugReport: DebugReport? {
        debugReports.max { $0.updatedAt < $1.updatedAt }
    }

    var stageScore: Double {
        switch stageEnum {
        case .planning:
            return latestPlanningSpec?.planningScore ?? 0
        case .design:
            return latestDesignSpec?.designScore ?? 0
        case .dev:
            return latestDevExecution?.changedFiles.isEmpty == false ? 100 : 0
        case .debug:
            return latestDebugReport?.coverageScore ?? 0
        case .backlog, .complete:
            return 0
        }
    }

    var artifactSummary: [String] {
        switch stageEnum {
        case .planning:
            return latestPlanningSpec?.summary ?? []
        case .design:
            return latestDesignSpec?.summary ?? []
        case .dev:
            return latestDevExecution?.summary ?? []
        case .debug:
            return latestDebugReport?.summary ?? []
        case .backlog, .complete:
            return []
        }
    }

    func setStage(_ stage: Stage) {
        self.stage = stage.rawValue
        self.updatedAt = Date()
    }

    func setStatus(_ status: TicketStatus) {
        self.status = status.rawValue
        self.updatedAt = Date()
    }

    func setHandoverState(_ state: TicketHandoverState, blockedReason: String? = nil) {
        self.handoverState = state.rawValue
        self.blockedReason = blockedReason
        self.updatedAt = Date()
    }
}
