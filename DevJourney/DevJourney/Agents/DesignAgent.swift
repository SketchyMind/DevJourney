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
        - Return valid JSON only. Do not wrap it in markdown fences.

        ## JSON Schema
        {
          "thoughts": ["short reasoning bullet"],
          "summary": ["handover-ready design bullet"],
          "clarificationQuestion": "single blocking question or null",
          "artifact": {
            "appPlacement": "where the feature lives in the app",
            "affectedScreens": ["screen"],
            "userFlow": ["step"],
            "components": ["component"],
            "microcopy": ["copy requirement"],
            "statesMatrix": ["state requirement"],
            "responsiveRules": ["responsive rule"],
            "accessibilityNotes": ["accessibility note"],
            "figmaRefs": ["optional figma ref"],
            "designScore": 0
          },
          "filesChanged": []
        }
        """
    }

    func buildInitialMessage(ticket: Ticket, project: Project) -> String {
        """
        Please create a design specification for the following ticket:

        **\(ticket.title)**

        \(ticket.ticketDescription)

        Provide UI/UX specs, component structure, data model changes, and any \
        architectural decisions needed. Include states, responsive rules, and accessibility.
        """
    }
}
