import Foundation

/// Parsed result from stage work (used by MCP tools when recording stage output).
struct AgentResponseResult {
    var thoughts: [String] = []
    var summary: [String] = []
    var filesChanged: [FileChange] = []
    var commitCount: Int = 0
    var needsClarification: Bool = false
    var clarificationQuestion: String?
}

/// Protocol for stage-specific agent prompt templates.
/// In MCP mode, these are used to generate prompt context that gets surfaced
/// to the external AI client via MCP prompt templates.
protocol StageAgent {
    var stageName: String { get }
    func buildSystemPrompt(ticket: Ticket, project: Project) -> String
    func buildInitialMessage(ticket: Ticket, project: Project) -> String
}

extension StageAgent {
    /// Shared context block included in all system prompts.
    func projectContext(project: Project, ticket: Ticket) -> String {
        var sections: [String] = []

        sections.append("""
        ## Project Context
        - Project: \(project.name)
        - Type: \(project.projectType)
        - Description: \(project.projectDescription)
        - Folder: \(project.folderPath)
        """)

        if !project.techStack.isEmpty {
            sections.append("""
            ## Tech Stack
            \(project.techStack)
            """)
        }

        if project.projectType == ProjectType.mobileApp.rawValue {
            let platforms = project.normalizedMobilePlatforms
                .compactMap(MobilePlatform.init(rawValue:))
                .map(\.displayName)
            if !platforms.isEmpty {
                sections.append("""
                ## Mobile Targets
                \(platforms.joined(separator: ", "))
                """)
            }
        }

        if !project.screenSizes.isEmpty {
            sections.append("""
            ## Target Screen Sizes
            \(project.screenSizes.joined(separator: ", "))
            - Responsive Behavior: \(project.responsiveBehaviorEnum.displayName)
            """)
        }

        if let repo = project.githubRepo, !repo.isEmpty {
            sections.append("""
            ## Repository
            - GitHub: \(repo)
            - Branch convention: feature/<ticket-id>-<slug>
            """)
        }

        var ticketSection = """
        ## Current Ticket
        - Title: \(ticket.title)
        - Description: \(ticket.ticketDescription)
        - Priority: \(ticket.priorityEnum.displayName)
        - Current Stage: \(ticket.stageEnum.displayName)
        """
        if !ticket.tags.isEmpty {
            ticketSection += "\n- Tags: \(ticket.tags.joined(separator: ", "))"
        }
        sections.append(ticketSection)

        let prior = priorStageContext(ticket: ticket)
        if !prior.isEmpty { sections.append(prior) }

        let clarifications = clarificationContext(ticket: ticket)
        if !clarifications.isEmpty { sections.append(clarifications) }

        return sections.joined(separator: "\n\n")
    }

    /// Collects completed session outputs for context chaining between stages.
    func priorStageContext(ticket: Ticket) -> String {
        let completed = ticket.sessions
            .filter { $0.endedAt != nil }
            .sorted { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }
        guard !completed.isEmpty else { return "" }

        var parts = ["## Prior Stage Outputs"]
        for session in completed {
            let name = Stage(rawValue: session.stage)?.displayName ?? session.stage
            parts.append("### \(name) Stage Output")
            if !session.resultSummary.isEmpty {
                parts.append(session.resultSummary.map { "- \($0)" }.joined(separator: "\n"))
            }
            if !session.filesChanged.isEmpty {
                parts.append("Files touched:")
                parts.append(session.filesChanged.map { "- \($0.path) (\($0.status))" }.joined(separator: "\n"))
            }
        }
        return parts.joined(separator: "\n")
    }

    func clarificationContext(ticket: Ticket) -> String {
        let answered = ticket.clarifications
            .filter { $0.stage == ticket.stage && $0.answer != nil }

        guard !answered.isEmpty else { return "" }

        let items = answered.map { item in
            "Q: \(item.question)\nA: \(item.answer ?? "")"
        }

        return """
        ## Clarifications Resolved
        \(items.joined(separator: "\n\n"))
        """
    }
}
