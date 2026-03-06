import Foundation
import SwiftData
import Combine

/// Manages active agent sessions and dispatches tickets to the appropriate stage agent.
@MainActor
final class AgentOrchestrator: ObservableObject {
    @Published var activeSessions: [String: AgentSession] = [:] // ticketId -> session

    private var runningTasks: [String: Task<Void, Never>] = [:]
    private let modelContext: ModelContext
    private let gitHubService: GitHubService

    init(modelContext: ModelContext, gitHubService: GitHubService? = nil) {
        self.modelContext = modelContext
        self.gitHubService = gitHubService ?? GitHubService()
    }

    // MARK: - Dispatch

    func dispatchTicket(_ ticket: Ticket, project: Project) {
        guard runningTasks[ticket.id] == nil else { return }

        let agent = agentForStage(ticket.stageEnum)
        let session = AgentSession(
            ticketId: ticket.id,
            stage: ticket.stage,
            modelUsed: ticket.aiModel
        )
        modelContext.insert(session)
        ticket.sessions.append(session)
        ticket.setStatus(.active)
        activeSessions[ticket.id] = session

        let task = Task {
            await runAgent(agent, ticket: ticket, project: project, session: session)
        }
        runningTasks[ticket.id] = task
    }

    // MARK: - Stop

    func stopAgent(ticketId: String) {
        runningTasks[ticketId]?.cancel()
        runningTasks.removeValue(forKey: ticketId)

        if let session = activeSessions.removeValue(forKey: ticketId) {
            session.end()
            session.addThought("Agent stopped by user.")
        }

        let localTicketId = ticketId
        let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == localTicketId })
        if let ticket = try? modelContext.fetch(descriptor).first {
            ticket.setStatus(.ready)
        }
        try? modelContext.save()
    }

    // MARK: - Resume after clarification

    func resumeAfterClarification(_ ticket: Ticket, project: Project, answer: String) {
        guard let session = activeSessions[ticket.id] else {
            dispatchTicket(ticket, project: project)
            return
        }

        session.addDialogEntry(role: "user", content: answer)
        let agent = agentForStage(ticket.stageEnum)

        let task = Task {
            await continueAgent(agent, ticket: ticket, project: project, session: session)
        }
        runningTasks[ticket.id] = task
    }

    // MARK: - Private

    private func agentForStage(_ stage: Stage) -> StageAgent {
        switch stage {
        case .planning: return PlanningAgent()
        case .design: return DesignAgent()
        case .dev: return DevAgent()
        case .debug: return DebugAgent()
        case .backlog, .complete: return PlanningAgent() // fallback
        }
    }

    private func runAgent(_ agent: StageAgent, ticket: Ticket, project: Project, session: AgentSession) async {
        session.addThought("Starting \(ticket.stageEnum.displayName) agent...")

        let systemPrompt = agent.buildSystemPrompt(ticket: ticket, project: project)
        let userMessage = agent.buildInitialMessage(ticket: ticket, project: project)

        session.addDialogEntry(role: "user", content: userMessage)

        do {
            let response = try await ClaudeAPIClient.shared.sendMessage(
                model: ticket.aiModel,
                systemPrompt: systemPrompt,
                messages: session.dialog.map { ($0.role, $0.content) }
            )

            guard !Task.isCancelled else { return }

            session.addDialogEntry(role: "assistant", content: response)
            await processAgentResponse(response, agent: agent, ticket: ticket, session: session)
        } catch {
            session.addThought("Error: \(error.localizedDescription)")
            ticket.setStatus(.ready)
        }

        try? modelContext.save()
    }

    private func continueAgent(_ agent: StageAgent, ticket: Ticket, project: Project, session: AgentSession) async {
        session.addThought("Resuming after clarification...")

        let systemPrompt = agent.buildSystemPrompt(ticket: ticket, project: project)

        do {
            let response = try await ClaudeAPIClient.shared.sendMessage(
                model: ticket.aiModel,
                systemPrompt: systemPrompt,
                messages: session.dialog.map { ($0.role, $0.content) }
            )

            guard !Task.isCancelled else { return }

            session.addDialogEntry(role: "assistant", content: response)
            await processAgentResponse(response, agent: agent, ticket: ticket, session: session)
        } catch {
            session.addThought("Error: \(error.localizedDescription)")
            ticket.setStatus(.ready)
        }

        try? modelContext.save()
    }

    private func processAgentResponse(_ response: String, agent: StageAgent, ticket: Ticket, session: AgentSession) async {
        let parsed = agent.parseResponse(response)

        for thought in parsed.thoughts {
            session.addThought(thought)
        }

        for file in parsed.filesChanged {
            session.filesChanged.append(file)
        }

        // Auto-commit if files were changed
        if !parsed.filesChanged.isEmpty {
            let projectId = ticket.projectId
            let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
            if let project = try? modelContext.fetch(descriptor).first {
                let repoPath = URL(fileURLWithPath: project.folderPath)
                let filePaths = parsed.filesChanged.map { $0.path }
                let commitMessage = "[\(ticket.stageEnum.displayName)] \(ticket.title)"
                let result = await gitHubService.createCommit(path: repoPath, message: commitMessage, files: filePaths)
                if result.success {
                    session.commitCount += 1
                    session.addThought("Auto-committed: \(result.commitHash ?? "unknown")")
                }
            }
        }

        session.commitCount += parsed.commitCount

        if parsed.needsClarification, let question = parsed.clarificationQuestion {
            ticket.setStatus(.clarify)
            let clarification = ClarificationItem(
                ticketId: ticket.id,
                stage: ticket.stage,
                question: question
            )
            modelContext.insert(clarification)
            ticket.clarifications.append(clarification)
            session.addThought("Waiting for clarification: \(question)")
        } else {
            // Stage complete
            session.end()
            session.resultSummary = parsed.summary
            runningTasks.removeValue(forKey: ticket.id)
            activeSessions.removeValue(forKey: ticket.id)

            let review = ReviewResult(
                ticketId: ticket.id,
                stage: ticket.stage
            )
            modelContext.insert(review)
            ticket.reviewResults.append(review)

            ticket.setStatus(.done)
            session.addThought("Stage complete. Ready for review.")
        }

        try? modelContext.save()
    }
}
