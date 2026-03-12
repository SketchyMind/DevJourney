import Foundation
import SwiftData

/// Type alias for MCP tool handlers.
typealias MCPToolHandler = @MainActor @Sendable ([String: Any], MCPToolContext) async throws -> String

/// Registry of all MCP tools exposed by DevJourney.
@MainActor
final class MCPToolRegistry {
    private var tools: [(definition: [String: Any], handler: MCPToolHandler)] = []

    init() {
        registerBoardTools()
        registerProjectTools()
        registerWorkflowTools()
        registerFileTools()
    }

    func allToolDefinitions() -> [[String: Any]] {
        tools.map { $0.definition }
    }

    func handler(for name: String) -> MCPToolHandler? {
        tools.first { ($0.definition["name"] as? String) == name }?.handler
    }

    private func register(name: String, description: String, inputSchema: [String: Any], handler: @escaping MCPToolHandler) {
        let definition: [String: Any] = [
            "name": name,
            "description": description,
            "inputSchema": inputSchema
        ]
        tools.append((definition: definition, handler: handler))
    }

    // MARK: - Board Tools

    private func registerBoardTools() {
        register(
            name: "get_board_state",
            description: "Get the current Kanban board state showing all columns and their tickets. Returns the full board with ticket IDs, titles, stages, statuses, and priorities.",
            inputSchema: [
                "type": "object",
                "properties": [String: Any](),
                "required": [String]()
            ]
        ) { _, ctx in
            let projects = ctx.projectService.loadProjects()
            guard let project = projects.first else {
                return "No project found. Create a project first."
            }

            let tickets = ctx.projectService.getProjectTickets(projectId: project.id)
            var board: [String: [[String: String]]] = [:]

            for stage in Stage.allCases {
                let stageTickets = tickets.filter { $0.stageEnum == stage }
                board[stage.displayName] = stageTickets.map { ticket in
                    [
                        "id": ticket.id,
                        "title": ticket.title,
                        "status": ticket.statusEnum.displayName,
                        "priority": ticket.priorityEnum.displayName,
                        "tags": ticket.tags.joined(separator: ", ")
                    ]
                }
            }

            let data = try JSONSerialization.data(withJSONObject: board, options: .prettyPrinted)
            return String(data: data, encoding: .utf8) ?? "{}"
        }

        register(
            name: "create_ticket",
            description: "Create a new ticket on the Kanban board. The ticket starts in the Backlog column.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "Short title for the ticket"],
                    "description": ["type": "string", "description": "Detailed description of what needs to be done"],
                    "priority": ["type": "string", "enum": ["Low", "Medium", "High"], "description": "Priority level (default: Medium)"],
                    "tags": ["type": "array", "items": ["type": "string"], "description": "Optional tags for categorization"],
                    "agent_count": ["type": "integer", "description": "Optional number of agents assigned to the ticket"]
                ],
                "required": ["title", "description"]
            ]
        ) { args, ctx in
            let projects = ctx.projectService.loadProjects()
            guard let project = projects.first else {
                return "No project found. Create a project first."
            }

            let title = args["title"] as? String ?? "Untitled"
            let description = args["description"] as? String ?? ""
            let priorityStr = args["priority"] as? String ?? "Medium"
            let priority = Priority(rawValue: priorityStr) ?? .medium
            let tags = args["tags"] as? [String] ?? []
            let agentCount = max(1, args["agent_count"] as? Int ?? 1)

            let ticket = ctx.projectService.createTicket(
                title: title,
                ticketDescription: description,
                priority: priority,
                projectId: project.id,
                tags: tags,
                agentCount: agentCount
            )

            return """
            Ticket created successfully:
            - ID: \(ticket.id)
            - Title: \(ticket.title)
            - Priority: \(ticket.priorityEnum.displayName)
            - Stage: Backlog
            """
        }

        register(
            name: "update_ticket",
            description: "Update an existing ticket's title, description, priority, or tags.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ticket_id": ["type": "string", "description": "The ticket ID to update"],
                    "title": ["type": "string", "description": "New title (optional)"],
                    "description": ["type": "string", "description": "New description (optional)"],
                    "priority": ["type": "string", "enum": ["Low", "Medium", "High"], "description": "New priority (optional)"],
                    "tags": ["type": "array", "items": ["type": "string"], "description": "New tags (replaces existing)"],
                    "agent_count": ["type": "integer", "description": "New agent count (optional)"]
                ],
                "required": ["ticket_id"]
            ]
        ) { args, ctx in
            guard let ticketId = args["ticket_id"] as? String else {
                return "Error: ticket_id is required"
            }

            let localId = ticketId
            let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == localId })
            guard let ticket = try ctx.modelContainer.mainContext.fetch(descriptor).first else {
                return "Error: Ticket not found with ID \(ticketId)"
            }

            if let title = args["title"] as? String { ticket.title = title }
            if let desc = args["description"] as? String { ticket.ticketDescription = desc }
            if let pri = args["priority"] as? String, let p = Priority(rawValue: pri) { ticket.priority = p.rawValue }
            if let tags = args["tags"] as? [String] { ticket.tags = tags }
            if let agentCount = args["agent_count"] as? Int { ticket.agentCount = max(1, agentCount) }

            ctx.projectService.updateTicket(ticket)
            return "Ticket \(ticketId) updated successfully."
        }

        register(
            name: "move_ticket",
            description: "Move a ticket to a different stage on the Kanban board. Valid stages: Backlog, Planning, Design, Dev, Debug, Complete.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ticket_id": ["type": "string", "description": "The ticket ID to move"],
                    "stage": ["type": "string", "enum": ["Backlog", "Planning", "Design", "Dev", "Debug", "Complete"], "description": "Target stage"]
                ],
                "required": ["ticket_id", "stage"]
            ]
        ) { args, ctx in
            guard let ticketId = args["ticket_id"] as? String,
                  let stageStr = args["stage"] as? String,
                  let stage = Stage(rawValue: stageStr)
            else {
                return "Error: ticket_id and valid stage are required"
            }

            let localId = ticketId
            let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == localId })
            guard let ticket = try ctx.modelContainer.mainContext.fetch(descriptor).first else {
                return "Error: Ticket not found with ID \(ticketId)"
            }

            ticket.setStage(stage)
            if stage == .complete {
                ticket.setStatus(.complete)
                ticket.setHandoverState(.complete)
            } else {
                ticket.setStatus(.ready)
                ticket.setHandoverState(.idle)
            }
            ctx.projectService.updateTicket(ticket)

            return "Ticket '\(ticket.title)' moved to \(stage.displayName)."
        }

        register(
            name: "get_ticket_details",
            description: "Get full details of a specific ticket including its session history, clarifications, and review results.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ticket_id": ["type": "string", "description": "The ticket ID"]
                ],
                "required": ["ticket_id"]
            ]
        ) { args, ctx in
            guard let ticketId = args["ticket_id"] as? String else {
                return "Error: ticket_id is required"
            }

            let localId = ticketId
            let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == localId })
            guard let ticket = try ctx.modelContainer.mainContext.fetch(descriptor).first else {
                return "Error: Ticket not found with ID \(ticketId)"
            }

            var details: [String: Any] = [
                "id": ticket.id,
                "title": ticket.title,
                "description": ticket.ticketDescription,
                "priority": ticket.priorityEnum.displayName,
                "stage": ticket.stageEnum.displayName,
                "status": ticket.statusEnum.displayName,
                "tags": ticket.tags,
                "created": ticket.createdAt.ISO8601Format(),
                "updated": ticket.updatedAt.ISO8601Format()
            ]

            // Session history
            let sessions: [[String: Any]] = ticket.sessions.map { session in
                [
                    "stage": session.stage,
                    "model": session.modelUsed,
                    "started": session.startedAt.ISO8601Format(),
                    "ended": session.endedAt?.ISO8601Format() ?? "in progress",
                    "thoughts": session.thoughts,
                    "summary": session.resultSummary,
                    "files_changed": session.filesChanged.map { "\($0.path) (\($0.status))" }
                ]
            }
            details["sessions"] = sessions

            // Clarifications
            let clarifications: [[String: Any]] = ticket.clarifications.map { c in
                [
                    "stage": c.stage,
                    "question": c.question,
                    "answer": c.answer ?? "unanswered",
                    "resolved": c.answer != nil
                ]
            }
            details["clarifications"] = clarifications

            let planningArtifact: Any = ticket.latestPlanningSpec.map { spec in
                [
                    "problem": spec.problem,
                    "scope_in": spec.scopeIn,
                    "scope_out": spec.scopeOut,
                    "acceptance_criteria": spec.acceptanceCriteria,
                    "assumptions": spec.assumptions,
                    "risks": spec.risks,
                    "definition_of_ready": spec.definitionOfReady,
                    "summary": spec.summary
                ]
            } ?? NSNull()
            let designArtifact: Any = ticket.latestDesignSpec.map { spec in
                [
                    "app_placement": spec.appPlacement,
                    "affected_screens": spec.affectedScreens,
                    "user_flow": spec.userFlow,
                    "components": spec.components,
                    "states_matrix": spec.statesMatrix,
                    "responsive_rules": spec.responsiveRules,
                    "summary": spec.summary
                ]
            } ?? NSNull()
            let devArtifact: Any = ticket.latestDevExecution.map { execution in
                [
                    "branch": execution.branch,
                    "changed_files": execution.changedFiles.map { "\($0.path) (\($0.status))" },
                    "implementation_notes": execution.implementationNotes,
                    "build_status": execution.buildStatus,
                    "summary": execution.summary
                ]
            } ?? NSNull()
            let debugArtifact: Any = ticket.latestDebugReport.map { report in
                [
                    "tested_scenarios": report.testedScenarios,
                    "failed_scenarios": report.failedScenarios,
                    "bug_items": report.bugItems,
                    "severity_summary": report.severitySummary,
                    "release_recommendation": report.releaseRecommendation,
                    "summary": report.summary
                ]
            } ?? NSNull()

            details["artifacts"] = [
                "planning": planningArtifact,
                "design": designArtifact,
                "dev": devArtifact,
                "debug": debugArtifact
            ]

            let data = try JSONSerialization.data(withJSONObject: details, options: .prettyPrinted)
            return String(data: data, encoding: .utf8) ?? "{}"
        }

        register(
            name: "delete_ticket",
            description: "Delete a ticket from the board. This is irreversible.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ticket_id": ["type": "string", "description": "The ticket ID to delete"]
                ],
                "required": ["ticket_id"]
            ]
        ) { args, ctx in
            guard let ticketId = args["ticket_id"] as? String else {
                return "Error: ticket_id is required"
            }

            let localId = ticketId
            let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == localId })
            guard let ticket = try ctx.modelContainer.mainContext.fetch(descriptor).first else {
                return "Error: Ticket not found with ID \(ticketId)"
            }

            let title = ticket.title
            ctx.projectService.deleteTicket(ticket)
            return "Ticket '\(title)' deleted."
        }
    }

    // MARK: - Project Tools

    private func registerProjectTools() {
        register(
            name: "get_project_info",
            description: "Get the current project's configuration including name, type, tech stack, screen sizes, and GitHub connection.",
            inputSchema: [
                "type": "object",
                "properties": [String: Any](),
                "required": [String]()
            ]
        ) { _, ctx in
            let projects = ctx.projectService.loadProjects()
            guard let project = projects.first else {
                return "No project found."
            }

            let info: [String: Any] = [
                "name": project.name,
                "description": project.projectDescription,
                "type": project.projectType,
                "folder": project.folderPath,
                "tech_stack": project.techStack,
                "screen_sizes": project.screenSizes,
                "responsive_behavior": project.responsiveBehavior,
                "mobile_platforms": project.normalizedMobilePlatforms,
                "github_repo": project.githubRepo ?? "not connected"
            ]

            let data = try JSONSerialization.data(withJSONObject: info, options: .prettyPrinted)
            return String(data: data, encoding: .utf8) ?? "{}"
        }

        register(
            name: "update_project_settings",
            description: "Update project settings like description, tech stack, screen sizes, or responsive behavior.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "description": ["type": "string", "description": "Project description"],
                    "project_type": ["type": "string", "enum": ["Web App", "Mobile App", "Desktop App", "Other"]],
                    "tech_stack": ["type": "string", "description": "Languages, frameworks, libraries"],
                    "screen_sizes": ["type": "array", "items": ["type": "string"], "description": "Target screen sizes: mobile, tablet, desktop"],
                    "responsive_behavior": ["type": "string", "enum": ["fluid", "fixed", "breakpoints"]],
                    "mobile_platforms": ["type": "array", "items": ["type": "string", "enum": ["ios", "android"]], "description": "Mobile targets for Mobile App projects"]
                ],
                "required": [String]()
            ]
        ) { args, ctx in
            let projects = ctx.projectService.loadProjects()
            guard let project = projects.first else {
                return "No project found."
            }

            if let desc = args["description"] as? String { project.projectDescription = desc }
            let newProjectType = (args["project_type"] as? String) ?? project.projectType
            project.projectType = newProjectType
            if let ts = args["tech_stack"] as? String { project.techStack = ts }
            if let ss = args["screen_sizes"] as? [String] { project.screenSizes = ss }
            if let rb = args["responsive_behavior"] as? String { project.responsiveBehavior = rb }
            if let mp = args["mobile_platforms"] as? [String] {
                project.mobilePlatforms = newProjectType == ProjectType.mobileApp.rawValue ? mp : []
            } else if newProjectType != ProjectType.mobileApp.rawValue {
                project.mobilePlatforms = []
            }

            ctx.projectService.updateProject(project)
            return "Project settings updated."
        }
    }

    // MARK: - Workflow Tools

    private func registerWorkflowTools() {
        register(
            name: "get_ticket_context",
            description: "Return the current ticket, project context, and latest artifact summaries for MCP agents.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ticket_id": ["type": "string", "description": "The ticket ID"]
                ],
                "required": ["ticket_id"]
            ]
        ) { args, ctx in
            guard let ticketId = args["ticket_id"] as? String else {
                return "Error: ticket_id is required"
            }

            let localId = ticketId
            let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == localId })
            guard let ticket = try ctx.modelContainer.mainContext.fetch(descriptor).first else {
                return "Error: Ticket not found with ID \(ticketId)"
            }

            let projects = ctx.projectService.loadProjects()
            guard let project = projects.first(where: { $0.id == ticket.projectId }) ?? projects.first else {
                return "Error: No project found"
            }

            let payload = ctx.workflowService.ticketContext(for: ticket, project: project)
            let data = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
            return String(data: data, encoding: .utf8) ?? "{}"
        }

        register(
            name: "upsert_planning_spec",
            description: "Create or update the planning artifact for a ticket in the Planning stage.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ticket_id": ["type": "string", "description": "The ticket ID"],
                    "problem": ["type": "string"],
                    "scope_in": ["type": "array", "items": ["type": "string"]],
                    "scope_out": ["type": "array", "items": ["type": "string"]],
                    "acceptance_criteria": ["type": "array", "items": ["type": "string"]],
                    "dependencies": ["type": "array", "items": ["type": "string"]],
                    "assumptions": ["type": "array", "items": ["type": "string"]],
                    "risks": ["type": "array", "items": ["type": "string"]],
                    "subtasks": ["type": "array", "items": ["type": "string"]],
                    "definition_of_ready": ["type": "array", "items": ["type": "string"]],
                    "summary": ["type": "array", "items": ["type": "string"]],
                    "planning_score": ["type": "number"]
                ],
                "required": ["ticket_id"]
            ]
        ) { args, ctx in
            guard let ticketId = args["ticket_id"] as? String else {
                return "Error: ticket_id is required"
            }
            let localId = ticketId
            let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == localId })
            guard let ticket = try ctx.modelContainer.mainContext.fetch(descriptor).first else {
                return "Error: Ticket not found with ID \(ticketId)"
            }

            ctx.workflowService.upsertPlanningSpec(
                for: ticket,
                input: PlanningSpecInput(
                    problem: args["problem"] as? String ?? "",
                    scopeIn: Self.stringArray(args["scope_in"]),
                    scopeOut: Self.stringArray(args["scope_out"]),
                    acceptanceCriteria: Self.stringArray(args["acceptance_criteria"]),
                    dependencies: Self.stringArray(args["dependencies"]),
                    assumptions: Self.stringArray(args["assumptions"]),
                    risks: Self.stringArray(args["risks"]),
                    subtasks: Self.stringArray(args["subtasks"]),
                    definitionOfReady: Self.stringArray(args["definition_of_ready"]),
                    summary: Self.stringArray(args["summary"]),
                    planningScore: Self.doubleValue(args["planning_score"])
                )
            )
            try? ctx.modelContainer.mainContext.save()
            ctx.workflowService.syncTicketStorage(for: ticket)
            return "Planning spec updated for ticket \(ticketId)."
        }

        register(
            name: "upsert_design_spec",
            description: "Create or update the design artifact for a ticket in the Design stage.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ticket_id": ["type": "string"],
                    "app_placement": ["type": "string"],
                    "affected_screens": ["type": "array", "items": ["type": "string"]],
                    "user_flow": ["type": "array", "items": ["type": "string"]],
                    "components": ["type": "array", "items": ["type": "string"]],
                    "microcopy": ["type": "array", "items": ["type": "string"]],
                    "states_matrix": ["type": "array", "items": ["type": "string"]],
                    "responsive_rules": ["type": "array", "items": ["type": "string"]],
                    "accessibility_notes": ["type": "array", "items": ["type": "string"]],
                    "figma_refs": ["type": "array", "items": ["type": "string"]],
                    "summary": ["type": "array", "items": ["type": "string"]],
                    "design_score": ["type": "number"]
                ],
                "required": ["ticket_id"]
            ]
        ) { args, ctx in
            guard let ticketId = args["ticket_id"] as? String else {
                return "Error: ticket_id is required"
            }
            let localId = ticketId
            let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == localId })
            guard let ticket = try ctx.modelContainer.mainContext.fetch(descriptor).first else {
                return "Error: Ticket not found with ID \(ticketId)"
            }

            ctx.workflowService.upsertDesignSpec(
                for: ticket,
                input: DesignSpecInput(
                    appPlacement: args["app_placement"] as? String ?? "",
                    affectedScreens: Self.stringArray(args["affected_screens"]),
                    userFlow: Self.stringArray(args["user_flow"]),
                    components: Self.stringArray(args["components"]),
                    microcopy: Self.stringArray(args["microcopy"]),
                    statesMatrix: Self.stringArray(args["states_matrix"]),
                    responsiveRules: Self.stringArray(args["responsive_rules"]),
                    accessibilityNotes: Self.stringArray(args["accessibility_notes"]),
                    figmaRefs: Self.stringArray(args["figma_refs"]),
                    summary: Self.stringArray(args["summary"]),
                    designScore: Self.doubleValue(args["design_score"])
                )
            )
            try? ctx.modelContainer.mainContext.save()
            ctx.workflowService.syncTicketStorage(for: ticket)
            return "Design spec updated for ticket \(ticketId)."
        }

        register(
            name: "upsert_dev_execution",
            description: "Create or update the development execution artifact for a ticket in the Dev stage.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ticket_id": ["type": "string"],
                    "branch": ["type": "string"],
                    "commit_list": ["type": "array", "items": ["type": "string"]],
                    "files_changed": ["type": "array", "items": ["type": "object"]],
                    "preview_urls": ["type": "array", "items": ["type": "string"]],
                    "implementation_notes": ["type": "array", "items": ["type": "string"]],
                    "build_status": ["type": "string", "enum": ["Not Run", "Pending", "Passed", "Failed"]],
                    "summary": ["type": "array", "items": ["type": "string"]],
                    "commit_message": ["type": "string"]
                ],
                "required": ["ticket_id"]
            ]
        ) { args, ctx in
            guard let ticketId = args["ticket_id"] as? String else {
                return "Error: ticket_id is required"
            }
            let localId = ticketId
            let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == localId })
            guard let ticket = try ctx.modelContainer.mainContext.fetch(descriptor).first else {
                return "Error: Ticket not found with ID \(ticketId)"
            }

            let buildStatus = BuildStatus(rawValue: args["build_status"] as? String ?? "") ?? .pending
            ctx.workflowService.upsertDevExecution(
                for: ticket,
                input: DevExecutionInput(
                    branch: args["branch"] as? String ?? "",
                    commitList: Self.stringArray(args["commit_list"]),
                    changedFiles: Self.fileChanges(args["files_changed"]),
                    previewURLs: Self.stringArray(args["preview_urls"]),
                    implementationNotes: Self.stringArray(args["implementation_notes"]),
                    buildStatus: buildStatus,
                    summary: Self.stringArray(args["summary"]),
                    commitMessage: args["commit_message"] as? String
                )
            )
            try? ctx.modelContainer.mainContext.save()
            ctx.workflowService.syncTicketStorage(for: ticket)
            return "Dev execution updated for ticket \(ticketId)."
        }

        register(
            name: "upsert_debug_report",
            description: "Create or update the debug report artifact for a ticket in the Debug stage.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ticket_id": ["type": "string"],
                    "tested_scenarios": ["type": "array", "items": ["type": "string"]],
                    "failed_scenarios": ["type": "array", "items": ["type": "string"]],
                    "bug_items": ["type": "array", "items": ["type": "string"]],
                    "severity_summary": ["type": "string"],
                    "release_recommendation": ["type": "string", "enum": ["Pending", "Ready", "Blocked"]],
                    "summary": ["type": "array", "items": ["type": "string"]],
                    "coverage_score": ["type": "number"]
                ],
                "required": ["ticket_id"]
            ]
        ) { args, ctx in
            guard let ticketId = args["ticket_id"] as? String else {
                return "Error: ticket_id is required"
            }
            let localId = ticketId
            let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == localId })
            guard let ticket = try ctx.modelContainer.mainContext.fetch(descriptor).first else {
                return "Error: Ticket not found with ID \(ticketId)"
            }

            let recommendation = ReleaseRecommendation(rawValue: args["release_recommendation"] as? String ?? "") ?? .pending
            ctx.workflowService.upsertDebugReport(
                for: ticket,
                input: DebugReportInput(
                    testedScenarios: Self.stringArray(args["tested_scenarios"]),
                    failedScenarios: Self.stringArray(args["failed_scenarios"]),
                    bugItems: Self.stringArray(args["bug_items"]),
                    severitySummary: args["severity_summary"] as? String ?? "",
                    releaseRecommendation: recommendation,
                    summary: Self.stringArray(args["summary"]),
                    coverageScore: Self.doubleValue(args["coverage_score"])
                )
            )
            try? ctx.modelContainer.mainContext.save()
            ctx.workflowService.syncTicketStorage(for: ticket)
            return "Debug report updated for ticket \(ticketId)."
        }

        register(
            name: "request_handover",
            description: "Validate whether the current stage artifact is complete enough to hand the ticket to the next stage.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ticket_id": ["type": "string"]
                ],
                "required": ["ticket_id"]
            ]
        ) { args, ctx in
            guard let ticketId = args["ticket_id"] as? String else {
                return "Error: ticket_id is required"
            }
            let localId = ticketId
            let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == localId })
            guard let ticket = try ctx.modelContainer.mainContext.fetch(descriptor).first else {
                return "Error: Ticket not found with ID \(ticketId)"
            }

            let gateResult = ctx.workflowService.requestHandover(for: ticket)
            let payload: [String: Any] = [
                "stage": gateResult.stage,
                "passed": gateResult.passed,
                "missing_fields": gateResult.missingFields,
                "blocking_questions": gateResult.blockingQuestions,
                "score": gateResult.score
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
            return String(data: data, encoding: .utf8) ?? "{}"
        }

        register(
            name: "request_clarification",
            description: "Create a blocking clarification thread for a ticket.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ticket_id": ["type": "string"],
                    "question": ["type": "string"]
                ],
                "required": ["ticket_id", "question"]
            ]
        ) { args, ctx in
            guard let ticketId = args["ticket_id"] as? String,
                  let question = args["question"] as? String else {
                return "Error: ticket_id and question are required"
            }

            let localId = ticketId
            let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == localId })
            guard let ticket = try ctx.modelContainer.mainContext.fetch(descriptor).first else {
                return "Error: Ticket not found with ID \(ticketId)"
            }

            _ = ctx.workflowService.requestClarification(for: ticket, question: question)
            try? ctx.modelContainer.mainContext.save()
            return "Clarification requested for ticket \(ticketId)."
        }

        register(
            name: "answer_clarification",
            description: "Answer the latest unresolved clarification for a ticket.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ticket_id": ["type": "string"],
                    "answer": ["type": "string"]
                ],
                "required": ["ticket_id", "answer"]
            ]
        ) { args, ctx in
            guard let ticketId = args["ticket_id"] as? String,
                  let answer = args["answer"] as? String else {
                return "Error: ticket_id and answer are required"
            }

            let localId = ticketId
            let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == localId })
            guard let ticket = try ctx.modelContainer.mainContext.fetch(descriptor).first else {
                return "Error: Ticket not found with ID \(ticketId)"
            }

            if let clarification = ticket.clarifications.last(where: { $0.answer == nil }) {
                ctx.workflowService.answerClarification(clarification, for: ticket, response: answer)
                return "Clarification answered for ticket \(ticketId)."
            }

            return "No pending clarification found for ticket \(ticketId)."
        }

        register(
            name: "submit_review_decision",
            description: "Record a review decision and, if approved, attempt the gated handover to the next stage.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ticket_id": ["type": "string"],
                    "approved": ["type": "boolean"],
                    "comment": ["type": "string"]
                ],
                "required": ["ticket_id", "approved"]
            ]
        ) { args, ctx in
            guard let ticketId = args["ticket_id"] as? String,
                  let approved = args["approved"] as? Bool else {
                return "Error: ticket_id and approved are required"
            }

            let localId = ticketId
            let descriptor = FetchDescriptor<Ticket>(predicate: #Predicate { $0.id == localId })
            guard let ticket = try ctx.modelContainer.mainContext.fetch(descriptor).first else {
                return "Error: Ticket not found with ID \(ticketId)"
            }

            let gateResult = ctx.workflowService.submitReviewDecision(
                for: ticket,
                approved: approved,
                comment: args["comment"] as? String
            )
            try? ctx.modelContainer.mainContext.save()

            if let gateResult {
                let payload: [String: Any] = [
                    "ticket_id": ticketId,
                    "approved": approved,
                    "stage": gateResult.stage,
                    "passed": gateResult.passed,
                    "missing_fields": gateResult.missingFields,
                    "blocking_questions": gateResult.blockingQuestions,
                    "score": gateResult.score,
                    "new_stage": ticket.stage,
                    "status": ticket.status
                ]
                let data = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
                return String(data: data, encoding: .utf8) ?? "{}"
            }

            return "Review decision recorded for ticket \(ticketId)."
        }
    }

    // MARK: - File Tools

    private func registerFileTools() {
        register(
            name: "list_project_files",
            description: "List files and directories in the project folder. Supports optional path relative to project root.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Relative path within the project (default: root)"],
                    "max_depth": ["type": "integer", "description": "Maximum directory depth to list (default: 2)"]
                ],
                "required": [String]()
            ]
        ) { args, ctx in
            let projects = ctx.projectService.loadProjects()
            guard let project = projects.first else {
                return "No project found."
            }

            let relativePath = args["path"] as? String ?? ""
            let maxDepth = args["max_depth"] as? Int ?? 2
            let basePath = URL(fileURLWithPath: project.folderPath)
            let targetPath = relativePath.isEmpty ? basePath : basePath.appendingPathComponent(relativePath)

            let fm = FileManager.default
            guard fm.fileExists(atPath: targetPath.path) else {
                return "Path does not exist: \(relativePath)"
            }

            var entries: [String] = []
            Self.listDirectory(at: targetPath, basePath: basePath, depth: 0, maxDepth: maxDepth, entries: &entries)

            return entries.isEmpty ? "Empty directory." : entries.joined(separator: "\n")
        }

        register(
            name: "read_project_file",
            description: "Read the contents of a file in the project folder.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Relative path to the file within the project"]
                ],
                "required": ["path"]
            ]
        ) { args, ctx in
            let projects = ctx.projectService.loadProjects()
            guard let project = projects.first else {
                return "No project found."
            }

            guard let relativePath = args["path"] as? String else {
                return "Error: path is required"
            }

            let filePath = URL(fileURLWithPath: project.folderPath).appendingPathComponent(relativePath)

            guard FileManager.default.fileExists(atPath: filePath.path) else {
                return "File not found: \(relativePath)"
            }

            guard let content = try? String(contentsOf: filePath, encoding: .utf8) else {
                return "Unable to read file (may be binary): \(relativePath)"
            }

            return content
        }

        register(
            name: "write_project_file",
            description: "Create or overwrite a UTF-8 text file in the project folder. Use this to implement code during the Dev stage.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Relative path to the file within the project"],
                    "content": ["type": "string", "description": "Complete UTF-8 text content to write"],
                    "create_directories": ["type": "boolean", "description": "Create missing parent directories (default: true)"]
                ],
                "required": ["path", "content"]
            ]
        ) { args, ctx in
            let projects = ctx.projectService.loadProjects()
            guard let project = projects.first else {
                return "No project found."
            }

            guard let relativePath = args["path"] as? String,
                  let content = args["content"] as? String else {
                return "Error: path and content are required"
            }

            let createDirectories = args["create_directories"] as? Bool ?? true
            let basePath = URL(fileURLWithPath: project.folderPath, isDirectory: true)

            guard let filePath = Self.safeProjectPath(basePath: basePath, relativePath: relativePath) else {
                return "Error: path must stay inside the project folder"
            }

            let fileManager = FileManager.default
            if createDirectories {
                try fileManager.createDirectory(
                    at: filePath.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            }

            try content.write(to: filePath, atomically: true, encoding: .utf8)

            let byteCount = content.lengthOfBytes(using: .utf8)
            return "Wrote \(byteCount) bytes to \(relativePath)."
        }

        register(
            name: "delete_project_file",
            description: "Delete a file from the project folder. Use with care when replacing generated files during development.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": "Relative path to the file within the project"]
                ],
                "required": ["path"]
            ]
        ) { args, ctx in
            let projects = ctx.projectService.loadProjects()
            guard let project = projects.first else {
                return "No project found."
            }

            guard let relativePath = args["path"] as? String else {
                return "Error: path is required"
            }

            let basePath = URL(fileURLWithPath: project.folderPath, isDirectory: true)
            guard let filePath = Self.safeProjectPath(basePath: basePath, relativePath: relativePath) else {
                return "Error: path must stay inside the project folder"
            }

            guard FileManager.default.fileExists(atPath: filePath.path) else {
                return "File not found: \(relativePath)"
            }

            try FileManager.default.removeItem(at: filePath)
            return "Deleted \(relativePath)."
        }

        register(
            name: "get_git_status",
            description: "Get the current git status of the project (branch, modified files, etc.).",
            inputSchema: [
                "type": "object",
                "properties": [String: Any](),
                "required": [String]()
            ]
        ) { _, ctx in
            let projects = ctx.projectService.loadProjects()
            guard let project = projects.first else {
                return "No project found."
            }

            let path = URL(fileURLWithPath: project.folderPath)
            let branch = await ctx.gitHubService.runGitAsync(at: path, args: ["rev-parse", "--abbrev-ref", "HEAD"]) ?? "unknown"
            let status = await ctx.gitHubService.runGitAsync(at: path, args: ["status", "--porcelain"]) ?? ""
            let log = await ctx.gitHubService.runGitAsync(at: path, args: ["log", "--oneline", "-5"]) ?? "No commits"

            return """
            Branch: \(branch)

            Modified files:
            \(status.isEmpty ? "(clean)" : status)

            Recent commits:
            \(log)
            """
        }
    }

    // MARK: - Helpers

    nonisolated private static func stringArray(_ value: Any?) -> [String] {
        if let values = value as? [String] {
            return values
        }
        if let values = value as? [Any] {
            return values.compactMap { $0 as? String }
        }
        return []
    }

    nonisolated private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        default:
            return nil
        }
    }

    nonisolated private static func fileChanges(_ value: Any?) -> [FileChange] {
        guard let items = value as? [[String: Any]] else { return [] }

        return items.map { item in
            FileChange(
                path: item["path"] as? String ?? "",
                status: item["status"] as? String ?? "modified",
                additions: item["additions"] as? Int ?? 0,
                deletions: item["deletions"] as? Int ?? 0
            )
        }
    }

    nonisolated private static func listDirectory(at url: URL, basePath: URL, depth: Int, maxDepth: Int, entries: inout [String]) {
        guard depth < maxDepth else { return }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return }

        let sorted = contents.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for item in sorted {
            let name = item.lastPathComponent
            if name.hasPrefix(".") { continue }

            let relativePath = item.path.replacingOccurrences(of: basePath.path + "/", with: "")
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let indent = String(repeating: "  ", count: depth)

            if isDir {
                entries.append("\(indent)\(relativePath)/")
                listDirectory(at: item, basePath: basePath, depth: depth + 1, maxDepth: maxDepth, entries: &entries)
            } else {
                entries.append("\(indent)\(relativePath)")
            }
        }
    }

    nonisolated private static func safeProjectPath(basePath: URL, relativePath: String) -> URL? {
        let candidate = basePath.appendingPathComponent(relativePath).standardizedFileURL
        let root = basePath.standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path == root.path || candidate.path.hasPrefix(rootPath) ? candidate : nil
    }
}
