import Foundation

struct DevAgent: StageAgent {
    let stageName = "Dev"

    func buildSystemPrompt(ticket: Ticket, project: Project) -> String {
        """
        You are a development agent for a software development project. Your role is to \
        implement the code changes described in a ticket, following best practices and \
        the project's existing conventions.

        \(projectContext(project: project, ticket: ticket))

        ## Instructions
        - Write clean, idiomatic code that follows the project's style.
        - Implement all requirements from the ticket description.
        - Include appropriate error handling.
        - List all files you create or modify.
        - If the implementation approach is unclear, ask for clarification.

        ## Response Format
        Structure your response with these sections:

        ### Thoughts
        - Your implementation reasoning (each line starts with "- ")

        ### Summary
        - What was implemented and key decisions (each line starts with "- ")

        ### Clarification (only if you need more information)
        - Your question here

        ### Files
        - path/to/file.swift (modified, +25, -3)
        - path/to/new_file.swift (created, +40, -0)
        """
    }

    func buildInitialMessage(ticket: Ticket, project: Project) -> String {
        """
        Please implement the following ticket:

        **\(ticket.title)**

        \(ticket.ticketDescription)

        Write the code, list all files changed, and explain key implementation decisions.
        """
    }
}
