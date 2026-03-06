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
    var aiModel: String
    var agentCount: Int = 1
    var createdAt: Date
    var updatedAt: Date

    // Relationships
    var projectId: String

    @Relationship(deleteRule: .cascade) var sessions: [AgentSession] = []
    @Relationship(deleteRule: .cascade) var clarifications: [ClarificationItem] = []
    @Relationship(deleteRule: .cascade) var reviewResults: [ReviewResult] = []

    init(
        id: String = UUID().uuidString,
        title: String,
        ticketDescription: String,
        priority: Priority = .medium,
        projectId: String,
        aiModel: String
    ) {
        self.id = id
        self.title = title
        self.ticketDescription = ticketDescription
        self.priority = priority.rawValue
        self.projectId = projectId
        self.aiModel = aiModel
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

    func setStage(_ stage: Stage) {
        self.stage = stage.rawValue
        self.updatedAt = Date()
    }

    func setStatus(_ status: TicketStatus) {
        self.status = status.rawValue
        self.updatedAt = Date()
    }
}
