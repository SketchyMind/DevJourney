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
        - Return valid JSON only. Do not wrap it in markdown fences.

        ## JSON Schema
        {
          "thoughts": ["short reasoning bullet"],
          "summary": ["debug result bullet"],
          "clarificationQuestion": "single blocking question or null",
          "artifact": {
            "testedScenarios": ["scenario"],
            "failedScenarios": ["scenario"],
            "bugItems": ["bug"],
            "severitySummary": "severity overview",
            "releaseRecommendation": "Ready",
            "coverageScore": 0
          },
          "filesChanged": [
            {"path": "path/to/file.swift", "status": "modified", "additions": 0, "deletions": 0}
          ]
        }
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
