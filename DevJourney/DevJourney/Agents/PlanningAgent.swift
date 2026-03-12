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
        - Return valid JSON only. Do not wrap it in markdown fences.

        ## JSON Schema
        {
          "thoughts": ["short reasoning bullet"],
          "summary": ["handover-ready planning bullet"],
          "clarificationQuestion": "single blocking question or null",
          "artifact": {
            "problem": "what problem is being solved",
            "scopeIn": ["included scope"],
            "scopeOut": ["excluded scope"],
            "acceptanceCriteria": ["testable criterion"],
            "dependencies": ["dependency"],
            "assumptions": ["assumption"],
            "risks": ["risk"],
            "subtasks": ["subtask"],
            "definitionOfReady": ["ready gate item"],
            "planningScore": 0
          },
          "filesChanged": []
        }
        """
    }

    func buildInitialMessage(ticket: Ticket, project: Project) -> String {
        """
        Please create a detailed plan for implementing the following ticket:

        **\(ticket.title)**

        \(ticket.ticketDescription)

        Break this down into specific, actionable tasks. Identify risks, acceptance criteria, \
        dependencies, and Definition of Ready items.
        """
    }
}
