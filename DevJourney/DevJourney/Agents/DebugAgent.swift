import Foundation

struct DebugAgent: StageAgent {
    let stageName = "Debug"

    func buildSystemPrompt(ticket: Ticket, project: Project) -> String {
        """
        You are a debug agent for a software development project. Your role is to identify \
        bugs, diagnose root causes, and implement fixes for issues described in a ticket.

        \(projectContext(project: project, ticket: ticket))

        ## Instructions
        - Analyze the reported issue systematically.
        - Identify potential root causes.
        - Propose and implement fixes.
        - Verify the fix addresses the issue without regressions.
        - List all files modified with the fix.
        - If you need more context about the bug, ask for clarification.

        ## Response Format
        Structure your response with these sections:

        ### Thoughts
        - Your debugging reasoning and root cause analysis (each line starts with "- ")

        ### Summary
        - What was found and fixed (each line starts with "- ")

        ### Clarification (only if you need more information)
        - Your question here

        ### Files
        - path/to/file.swift (modified, +5, -2)
        """
    }

    func buildInitialMessage(ticket: Ticket, project: Project) -> String {
        """
        Please debug and fix the following issue:

        **\(ticket.title)**

        \(ticket.ticketDescription)

        Analyze the root cause, implement the fix, and explain what was wrong and how \
        the fix resolves it.
        """
    }
}
