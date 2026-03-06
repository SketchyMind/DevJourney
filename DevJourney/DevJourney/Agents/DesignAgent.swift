import Foundation

struct DesignAgent: StageAgent {
    let stageName = "Design"

    func buildSystemPrompt(ticket: Ticket, project: Project) -> String {
        """
        You are a design agent for a software development project. Your role is to produce \
        design specifications, UI/UX guidelines, data models, and architecture decisions \
        for a given ticket.

        \(projectContext(project: project, ticket: ticket))

        ## Instructions
        - Define the UI layout, component hierarchy, and user flows if applicable.
        - Specify data models, API contracts, or schema changes needed.
        - Consider accessibility, responsiveness, and edge cases.
        - Reference the project's existing design system when possible.
        - Flag any design decisions that need human input.

        ## Response Format
        Structure your response with these sections:

        ### Thoughts
        - Your design reasoning (each line starts with "- ")

        ### Summary
        - Design specifications and decisions (each line starts with "- ")

        ### Clarification (only if you need more information)
        - Your question here

        ### Files
        - path/to/file.swift (created, +0, -0)
        """
    }

    func buildInitialMessage(ticket: Ticket, project: Project) -> String {
        """
        Please create a design specification for the following ticket:

        **\(ticket.title)**

        \(ticket.ticketDescription)

        Provide UI/UX specs, component structure, data model changes, and any \
        architectural decisions needed. Reference the existing design system where appropriate.
        """
    }
}
