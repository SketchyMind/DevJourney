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
        - Return valid JSON only. Do not wrap it in markdown fences.

        ## JSON Schema
        {
          "thoughts": ["short reasoning bullet"],
          "summary": ["implementation outcome bullet"],
          "clarificationQuestion": "single blocking question or null",
          "artifact": {
            "branch": "current branch name",
            "commitList": ["existing commit hash if any"],
            "filesChanged": [
              {"path": "path/to/file.swift", "status": "modified", "additions": 0, "deletions": 0}
            ],
            "previewURLs": ["preview url if available"],
            "implementationNotes": ["implementation note"],
            "buildStatus": "Pending",
            "commitMessage": "optional commit message"
          },
          "filesChanged": [
            {"path": "path/to/file.swift", "status": "modified", "additions": 0, "deletions": 0}
          ]
        }
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
