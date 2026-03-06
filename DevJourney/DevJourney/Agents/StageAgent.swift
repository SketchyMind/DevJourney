import Foundation

/// Parsed result from an agent's response.
struct AgentResponseResult {
    var thoughts: [String] = []
    var summary: [String] = []
    var filesChanged: [FileChange] = []
    var commitCount: Int = 0
    var needsClarification: Bool = false
    var clarificationQuestion: String?
}

/// Protocol that all stage-specific agents conform to.
protocol StageAgent {
    var stageName: String { get }

    func buildSystemPrompt(ticket: Ticket, project: Project) -> String
    func buildInitialMessage(ticket: Ticket, project: Project) -> String
    func parseResponse(_ response: String) -> AgentResponseResult
}

extension StageAgent {
    /// Shared context block included in all system prompts.
    func projectContext(project: Project, ticket: Ticket) -> String {
        var sections: [String] = []

        // Core project info
        sections.append("""
        ## Project Context
        - Project: \(project.name)
        - Type: \(project.projectType)
        - Description: \(project.projectDescription)
        - Folder: \(project.folderPath)
        """)

        // Tech stack & screen sizes
        if !project.techStack.isEmpty {
            sections.append("""
            ## Tech Stack
            \(project.techStack)
            """)
        }

        if !project.screenSizes.isEmpty {
            sections.append("""
            ## Target Screen Sizes
            \(project.screenSizes.joined(separator: ", "))
            - Responsive Behavior: \(project.responsiveBehaviorEnum.displayName)
            """)
        }

        // GitHub repo
        if let repo = project.githubRepo, !repo.isEmpty {
            sections.append("""
            ## Repository
            - GitHub: \(repo)
            - Branch convention: feature/<ticket-id>-<slug>
            """)
        }

        // AI model metadata
        if let config = AIModelConfig.config(for: ticket.aiModel) {
            sections.append("""
            ## AI Model
            - Provider: \(config.provider.displayName)
            - Model: \(config.displayName)
            - Context window: \(config.contextWindow) tokens
            """)
        }

        // Ticket info
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

        // Prior stage outputs
        let prior = priorStageContext(ticket: ticket)
        if !prior.isEmpty { sections.append(prior) }

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

    /// Default response parser that looks for structured markers in the response.
    func parseResponse(_ response: String) -> AgentResponseResult {
        var result = AgentResponseResult()
        let lines = response.components(separatedBy: "\n")

        var currentSection: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## Thoughts") || trimmed.hasPrefix("### Thoughts") {
                currentSection = "thoughts"
                continue
            } else if trimmed.hasPrefix("## Summary") || trimmed.hasPrefix("### Summary") {
                currentSection = "summary"
                continue
            } else if trimmed.hasPrefix("## Clarification") || trimmed.hasPrefix("### Clarification") {
                currentSection = "clarification"
                result.needsClarification = true
                continue
            } else if trimmed.hasPrefix("## Files") || trimmed.hasPrefix("### Files") {
                currentSection = "files"
                continue
            } else if trimmed.hasPrefix("##") || trimmed.hasPrefix("###") {
                currentSection = nil
                continue
            }

            guard !trimmed.isEmpty else { continue }

            switch currentSection {
            case "thoughts":
                let thought = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed
                result.thoughts.append(thought)
            case "summary":
                let item = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed
                result.summary.append(item)
            case "clarification":
                if result.clarificationQuestion == nil {
                    let q = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed
                    result.clarificationQuestion = q
                }
            case "files":
                if let file = parseFileChangeLine(trimmed) {
                    result.filesChanged.append(file)
                }
            default:
                break
            }
        }

        // If no structured format, treat entire response as summary
        if result.thoughts.isEmpty && result.summary.isEmpty && !result.needsClarification {
            result.summary = [response]
        }

        return result
    }

    private func parseFileChangeLine(_ line: String) -> FileChange? {
        // Expected: "- path/to/file.swift (modified, +10, -3)"
        let cleaned = line.hasPrefix("- ") ? String(line.dropFirst(2)) : line
        let parts = cleaned.components(separatedBy: " (")
        guard parts.count >= 1 else { return nil }
        let path = parts[0].trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }

        var status = "modified"
        var additions = 0
        var deletions = 0

        if parts.count >= 2 {
            let meta = parts[1].replacingOccurrences(of: ")", with: "")
            let metaParts = meta.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if let first = metaParts.first {
                status = first
            }
            for part in metaParts {
                if part.hasPrefix("+"), let n = Int(part.dropFirst()) {
                    additions = n
                } else if part.hasPrefix("-"), let n = Int(part.dropFirst()) {
                    deletions = n
                }
            }
        }

        return FileChange(path: path, status: status, additions: additions, deletions: deletions)
    }
}
