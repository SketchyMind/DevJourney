import Foundation

/// MCP prompt templates for external clients that want to participate in
/// DevJourney's artifact-based stage workflow.
enum MCPPromptTemplates {

    static func allPromptDefinitions() -> [[String: Any]] {
        [
            promptDefinition(
                name: "planning_agent",
                description: "Planning-stage workflow. Pull ticket context, produce a planning artifact, request clarification if blocked, and validate the handover gate."
            ),
            promptDefinition(
                name: "design_agent",
                description: "Design-stage workflow. Pull ticket context, produce a design artifact, request clarification if blocked, and validate the handover gate."
            ),
            promptDefinition(
                name: "dev_agent",
                description: "Development-stage workflow. Pull ticket context, produce a dev execution artifact, request clarification if blocked, and validate the handover gate."
            ),
            promptDefinition(
                name: "debug_agent",
                description: "Debug-stage workflow. Pull ticket context, produce a debug report artifact, request clarification if blocked, and validate the handover gate."
            )
        ]
    }

    static func getPrompt(name: String, arguments: [String: Any]) -> [String: Any]? {
        guard let stageConfig = stageConfig(for: name) else {
            return nil
        }

        let ticketId = arguments["ticket_id"] as? String ?? ""
        let runNotes = arguments["run_notes"] as? String ?? ""

        let systemPrompt = """
        You are DevJourney's \(stageConfig.stageName) agent operating through MCP.

        Your job is to create a durable stage artifact, not a free-form chat summary.

        Workflow:
        1. Call `get_ticket_context` with `ticket_id`.
        2. Read the project details, current ticket, all clarifications, and prior-stage artifacts.
        3. Treat answered clarifications as authoritative operator instructions for this run.
        4. If required information is still missing or contradictory after considering those answers, call `request_clarification` and stop.
        5. When you have enough information, call `\(stageConfig.upsertTool)` with a complete artifact payload.
        6. After writing the artifact, call `request_handover`.
        7. If the handover gate fails, translate the missing information into a focused `request_clarification`.

        Rules:
        - Do not invent repo facts, implementation status, or approvals.
        - Keep artifacts concrete and stage-appropriate.
        - Prefer arrays of short, explicit statements over prose paragraphs inside artifact fields.
        - Do not call deprecated tools like `submit_stage_output` or `ask_clarification`.
        - Do not call `submit_review_decision`; review is a separate step.
        - Never repeat or ignore a clarification that already has an answer in the ticket context.
        - If the user answered in plain text, incorporate that answer directly into the artifact instead of asking the same question again.

        Required MCP tools for this run:
        - `get_ticket_context`
        - `\(stageConfig.upsertTool)`
        - `request_handover`
        - `request_clarification`
        \(stageConfig.implementationTools)
        """

        let userMessage = """
        Execute the \(stageConfig.stageName.lowercased()) workflow for ticket `\(ticketId)`.

        Artifact contract:
        \(stageConfig.artifactContract)

        \(runNotes.isEmpty ? "" : "Additional run notes:\n\(runNotes)\n")
        Start by calling `get_ticket_context`.
        """

        return [
            "description": stageConfig.description,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": systemPrompt + "\n\n---\n\n" + userMessage
                        ]
                    ]
                ]
            ]
        ]
    }

    static func renderedPromptText(name: String, arguments: [String: Any]) -> String? {
        guard let prompt = getPrompt(name: name, arguments: arguments),
              let messages = prompt["messages"] as? [[String: Any]],
              let firstMessage = messages.first,
              let content = firstMessage["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            return nil
        }
        return text
    }

    private static func promptDefinition(name: String, description: String) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "arguments": [
                [
                    "name": "ticket_id",
                    "description": "The DevJourney ticket ID to work on",
                    "required": true
                ],
                [
                    "name": "run_notes",
                    "description": "Optional extra operator instructions for this specific run",
                    "required": false
                ]
            ]
        ]
    }

    private static func stageConfig(for name: String) -> StagePromptConfig? {
        switch name {
        case "planning_agent":
            return StagePromptConfig(
                stageName: "Planning",
                upsertTool: "upsert_planning_spec",
                description: "Create the planning artifact for a ticket and validate whether it is ready for design handoff.",
                artifactContract: """
                Fill fields such as `problem`, `scope_in`, `scope_out`, `acceptance_criteria`, `dependencies`, `assumptions`, `risks`, `subtasks`, `definition_of_ready`, `summary`, and `planning_score`.
                """,
                implementationTools: ""
            )
        case "design_agent":
            return StagePromptConfig(
                stageName: "Design",
                upsertTool: "upsert_design_spec",
                description: "Create the design artifact for a ticket and validate whether it is ready for development handoff.",
                artifactContract: """
                Fill fields such as `app_placement`, `affected_screens`, `user_flow`, `components`, `microcopy`, `states_matrix`, `responsive_rules`, `accessibility_notes`, `figma_refs`, `summary`, and `design_score`.
                """,
                implementationTools: ""
            )
        case "dev_agent":
            return StagePromptConfig(
                stageName: "Development",
                upsertTool: "upsert_dev_execution",
                description: "Create the development execution artifact for a ticket and validate whether it is ready for debug handoff.",
                artifactContract: """
                First implement the planned work in the project files using MCP file tools. Read the relevant files, create or edit code files, then inspect git status and summarize what changed. Fill fields such as `branch`, `commit_list`, `files_changed`, `preview_urls`, `implementation_notes`, `build_status`, `summary`, and `commit_message`.
                """,
                implementationTools: """
                - `list_project_files`
                - `read_project_file`
                - `write_project_file`
                - `delete_project_file`
                - `get_git_status`
                """
            )
        case "debug_agent":
            return StagePromptConfig(
                stageName: "Debug",
                upsertTool: "upsert_debug_report",
                description: "Create the debug artifact for a ticket and validate whether it is ready for completion review.",
                artifactContract: """
                Fill fields such as `tested_scenarios`, `failed_scenarios`, `bug_items`, `severity_summary`, `release_recommendation`, `summary`, and `coverage_score`.
                """,
                implementationTools: ""
            )
        default:
            return nil
        }
    }
}

private struct StagePromptConfig {
    let stageName: String
    let upsertTool: String
    let description: String
    let artifactContract: String
    let implementationTools: String
}
