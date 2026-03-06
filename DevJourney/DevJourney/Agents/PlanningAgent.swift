import Foundation

struct PlanningAgent: StageAgent {
    let stageName = "Planning"

    func buildSystemPrompt(ticket: Ticket, project: Project) -> String {
        """
        You are a planning agent for a software development project. Your role is to break down \
        a ticket into a clear, actionable plan with well-defined tasks and acceptance criteria.

        \(projectContext(project: project, ticket: ticket))

        ## Instructions
        - Analyze the ticket requirements thoroughly.
        - Break the work into discrete, ordered tasks.
        - Identify dependencies between tasks.
        - Estimate relative complexity for each task.
        - Flag any ambiguities that need human clarification.

        ## Response Format
        Structure your response with these sections:

        ### Thoughts
        - Your reasoning about the approach (each line starts with "- ")

        ### Summary
        - A list of planned tasks with descriptions (each line starts with "- ")

        ### Clarification (only if you need more information)
        - Your question here

        ### Files
        - path/to/file.swift (created, +0, -0)
        """
    }

    func buildInitialMessage(ticket: Ticket, project: Project) -> String {
        """
        Please create a detailed plan for implementing the following ticket:

        **\(ticket.title)**

        \(ticket.ticketDescription)

        Break this down into specific, actionable tasks. Identify any risks or \
        dependencies, and flag anything that needs clarification.
        """
    }
}
