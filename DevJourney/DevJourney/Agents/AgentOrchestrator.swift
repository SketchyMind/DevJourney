import Foundation
import SwiftData
import Combine

/// Manages active agent sessions and tracks ticket workflow state.
/// In MCP mode, the actual AI work is done by the external MCP client —
/// this orchestrator handles session lifecycle and state transitions.
@MainActor
final class AgentOrchestrator: ObservableObject {
    @Published var activeSessions: [String: AgentSession] = [:] // ticketId -> session

    private let modelContext: ModelContext
    private let gitHubService: GitHubService

    init(modelContext: ModelContext, gitHubService: GitHubService? = nil) {
        self.modelContext = modelContext
        self.gitHubService = gitHubService ?? GitHubService()
    }

    // MARK: - Session Management

    /// Start a session for a ticket (marks it as active on the board).
    func startSession(for ticket: Ticket) {
        guard activeSessions[ticket.id] == nil else { return }

        let session = AgentSession(
            ticketId: ticket.id,
            stage: ticket.stage,
            modelUsed: "mcp-client"
        )
        modelContext.insert(session)
        ticket.sessions.append(session)
        ticket.setStatus(.active)
        activeSessions[ticket.id] = session
        try? modelContext.save()
    }

    /// End a session for a ticket.
    func endSession(ticketId: String) {
        if let session = activeSessions.removeValue(forKey: ticketId) {
            session.end()
        }

        let localTicketId = ticketId
        let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == localTicketId })
        if let ticket = try? modelContext.fetch(descriptor).first {
            ticket.setStatus(.ready)
        }
        try? modelContext.save()
    }

    /// Auto-commit changed files for a ticket.
    func commitChanges(for ticket: Ticket, files: [String], message: String) async {
        let projectId = ticket.projectId
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
        guard let project = try? modelContext.fetch(descriptor).first else { return }

        let repoPath = URL(fileURLWithPath: project.folderPath)
        let result = await gitHubService.createCommit(path: repoPath, message: message, files: files)

        if result.success, let session = activeSessions[ticket.id] {
            session.commitCount += 1
            session.addThought("Auto-committed: \(result.commitHash ?? "unknown")")
        }
        try? modelContext.save()
    }
}
