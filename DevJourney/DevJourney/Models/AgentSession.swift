import Foundation
import SwiftData

struct DialogEntry: Codable, Hashable, Sendable {
    let role: String // "user" or "assistant"
    let content: String
    let timestamp: Date
}

struct FileChange: Codable, Hashable, Sendable {
    let path: String
    let status: String // "modified", "created", "deleted"
    let additions: Int
    let deletions: Int
}

@Model
final class AgentSession {
    @Attribute(.unique) var id: String
    var ticketId: String
    var stage: String
    var startedAt: Date
    var endedAt: Date?
    var providerId: String?
    var modelUsed: String
    var liveResponse: String = ""
    var errorMessage: String?
    var thoughts: [String] = []
    var dialog: [DialogEntry] = []
    var executionEvents: [AgentExecutionEvent] = []
    var resultSummary: [String] = []
    var filesChanged: [FileChange] = []
    var commitCount: Int = 0
    var durationSeconds: Int {
        let end = endedAt ?? Date()
        return Int(end.timeIntervalSince(startedAt))
    }

    init(
        id: String = UUID().uuidString,
        ticketId: String,
        stage: String,
        providerId: String? = nil,
        modelUsed: String
    ) {
        self.id = id
        self.ticketId = ticketId
        self.stage = stage
        self.providerId = providerId
        self.modelUsed = modelUsed
        self.startedAt = Date()
    }

    func addThought(_ thought: String) {
        self.thoughts.append(thought)
    }

    func addDialogEntry(role: String, content: String) {
        let entry = DialogEntry(role: role, content: content, timestamp: Date())
        self.dialog.append(entry)
    }

    func appendAssistantDelta(_ delta: String) {
        liveResponse += delta

        if let index = dialog.lastIndex(where: { $0.role == "assistant" }) {
            let existing = dialog[index]
            dialog[index] = DialogEntry(
                role: existing.role,
                content: existing.content + delta,
                timestamp: existing.timestamp
            )
        } else {
            dialog.append(DialogEntry(role: "assistant", content: delta, timestamp: Date()))
        }
    }

    func addEvent(
        type: AgentExecutionEventType,
        message: String,
        metadata: [String: String] = [:]
    ) {
        executionEvents.append(
            AgentExecutionEvent(type: type, message: message, metadata: metadata)
        )
    }

    func end() {
        self.endedAt = Date()
    }
}
