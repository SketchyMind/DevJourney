import Foundation
import SwiftData

struct DialogEntry: Codable {
    let role: String // "user" or "assistant"
    let content: String
    let timestamp: Date
}

struct FileChange: Codable {
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
    var modelUsed: String
    var thoughts: [String] = []
    var dialog: [DialogEntry] = []
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
        modelUsed: String
    ) {
        self.id = id
        self.ticketId = ticketId
        self.stage = stage
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

    func end() {
        self.endedAt = Date()
    }
}
