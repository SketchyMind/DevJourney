import Combine
import Foundation
import SwiftData

struct PlanningSpecInput: Sendable {
    var problem: String
    var scopeIn: [String]
    var scopeOut: [String]
    var acceptanceCriteria: [String]
    var dependencies: [String]
    var assumptions: [String]
    var risks: [String]
    var subtasks: [String]
    var definitionOfReady: [String]
    var summary: [String]
    var planningScore: Double?
}

struct DesignSpecInput: Sendable {
    var appPlacement: String
    var affectedScreens: [String]
    var userFlow: [String]
    var components: [String]
    var microcopy: [String]
    var statesMatrix: [String]
    var responsiveRules: [String]
    var accessibilityNotes: [String]
    var figmaRefs: [String]
    var summary: [String]
    var designScore: Double?
}

struct DevExecutionInput: Sendable {
    var branch: String
    var commitList: [String]
    var changedFiles: [FileChange]
    var previewURLs: [String]
    var implementationNotes: [String]
    var buildStatus: BuildStatus
    var summary: [String]
    var commitMessage: String?
}

struct DebugReportInput: Sendable {
    var testedScenarios: [String]
    var failedScenarios: [String]
    var bugItems: [String]
    var severitySummary: String
    var releaseRecommendation: ReleaseRecommendation
    var summary: [String]
    var coverageScore: Double?
}

@MainActor
final class TicketWorkflowService: ObservableObject {
    @Published private(set) var activeSessions: [String: AgentSession] = [:]

    private let modelContainer: ModelContainer
    private let projectService: ProjectService
    private let gitHubService: GitHubService
    private let localTicketStore: LocalTicketStore
    private let externalRunnerService: ExternalAgentRunnerService
    private let providerRegistry = AgentProviderRegistry()
    private var runningTasks: [String: Task<Void, Never>] = [:]

    init(
        modelContainer: ModelContainer,
        projectService: ProjectService,
        gitHubService: GitHubService,
        localTicketStore: LocalTicketStore,
        externalRunnerService: ExternalAgentRunnerService? = nil
    ) {
        self.modelContainer = modelContainer
        self.projectService = projectService
        self.gitHubService = gitHubService
        self.localTicketStore = localTicketStore
        self.externalRunnerService = externalRunnerService ?? ExternalAgentRunnerService()
    }

    private var context: ModelContext {
        modelContainer.mainContext
    }

    private func providerBlockedReason(for ticket: Ticket, externalClientAvailable: Bool) -> String {
        let base = "No enabled provider configured for \(ticket.stageEnum.displayName)."
        if externalClientAvailable {
            return base + " DevJourney can also run this stage through Claude Code or Codex via MCP, but no local runner could be started."
        }
        return base + " Install or sign in to Claude Code or Codex, or configure an in-app provider."
    }

    private func missingKeyBlockedReason(
        providerName: String,
        ticket: Ticket,
        externalClientAvailable: Bool
    ) -> String {
        let base = "Missing API key for \(providerName)."
        if externalClientAvailable {
            return base + " DevJourney can also run this stage through Claude Code or Codex via MCP, but no local runner could be started."
        }
        return base + " Install or sign in to Claude Code or Codex, or add the provider key in Settings."
    }

    private func mcpPromptName(for stage: Stage) -> String? {
        switch stage {
        case .planning:
            return "planning_agent"
        case .design:
            return "design_agent"
        case .dev:
            return "dev_agent"
        case .debug:
            return "debug_agent"
        case .backlog, .complete:
            return nil
        }
    }

    func startStage(
        for ticket: Ticket,
        project: Project,
        mcpConnectionStatus: MCPConnectionStatusSnapshot = MCPConnectionStatusSnapshot(
            clientName: nil,
            lastSeenAt: nil,
            serverPID: nil
        ),
        claudeRegistrationStatus: ClaudeMCPRegistrationStatus = .init(mode: .notConfigured)
    ) {
        guard runningTasks[ticket.id] == nil else { return }

        projectService.ensureDefaultProviderConfigs(for: project)
        let externalClient = externalRunnerService.resolvePreferredClient(
            connectionStatus: mcpConnectionStatus,
            claudeStatus: claudeRegistrationStatus
        )

        guard let providerConfig = resolveProviderConfig(for: ticket.stageEnum, project: project) else {
            if let externalClient {
                startExternalStage(for: ticket, project: project, client: externalClient)
                return
            }
            ticket.setStatus(.clarify)
            ticket.setHandoverState(
                .blocked,
                blockedReason: providerBlockedReason(
                    for: ticket,
                    externalClientAvailable: externalClient != nil
                )
            )
            try? context.save()
            syncTicketStorage(for: ticket, project: project)
            return
        }

        guard let apiKey = KeychainService.shared.readProviderAPIKey(reference: providerConfig.apiKeyReference) else {
            if let externalClient {
                startExternalStage(for: ticket, project: project, client: externalClient)
                return
            }
            ticket.setStatus(.clarify)
            ticket.setHandoverState(
                .blocked,
                blockedReason: missingKeyBlockedReason(
                    providerName: providerConfig.displayName,
                    ticket: ticket,
                    externalClientAvailable: externalClient != nil
                )
            )
            try? context.save()
            syncTicketStorage(for: ticket, project: project)
            return
        }

        let model = resolveModel(for: ticket.stageEnum, project: project, providerConfig: providerConfig)
        let runtimeConfiguration = ResolvedProviderConfiguration(providerConfig)
        let stageAgent = agent(for: ticket.stageEnum)
        let request = AgentExecutionRequest(
            ticketId: ticket.id,
            stage: ticket.stage,
            providerId: runtimeConfiguration.id,
            model: model,
            systemPrompt: stageAgent.buildSystemPrompt(ticket: ticket, project: project),
            userPrompt: stageAgent.buildInitialMessage(ticket: ticket, project: project),
            toolPolicy: "manual-review"
        )

        let session = AgentSession(
            ticketId: ticket.id,
            stage: ticket.stage,
            providerId: providerConfig.id,
            modelUsed: model
        )
        context.insert(session)
        ticket.sessions.append(session)
        ticket.activeProviderConfigId = providerConfig.id
        ticket.activeModel = model
        ticket.setStatus(.active)
        ticket.setHandoverState(.running)
        session.addDialogEntry(role: "user", content: request.userPrompt)
        session.addEvent(
            type: .started,
            message: "Started \(ticket.stageEnum.displayName) with \(providerConfig.displayName) / \(model)."
        )
        activeSessions[ticket.id] = session
        try? context.save()
        syncTicketStorage(for: ticket, project: project)

        runningTasks[ticket.id] = Task { [weak self] in
            guard let self else { return }
            await self.runStage(
                request: request,
                ticket: ticket,
                project: project,
                providerConfig: providerConfig,
                runtimeConfiguration: runtimeConfiguration,
                apiKey: apiKey,
                session: session
            )
        }
    }

    private func startExternalStage(for ticket: Ticket, project: Project, client: ExternalAgentClient) {
        let prompt = externalPrompt(for: ticket, project: project)
        let session = AgentSession(
            ticketId: ticket.id,
            stage: ticket.stage,
            providerId: client.providerDisplayName,
            modelUsed: client.modelDisplayName
        )
        context.insert(session)
        ticket.sessions.append(session)
        ticket.activeProviderConfigId = client.providerDisplayName
        ticket.activeModel = client.modelDisplayName
        ticket.setStatus(.active)
        ticket.setHandoverState(.running)
        session.addDialogEntry(role: "user", content: prompt)
        session.addThought("Launching \(client.displayName) for \(ticket.stageEnum.displayName).")
        session.addEvent(
            type: .started,
            message: "Started \(ticket.stageEnum.displayName) with \(client.displayName) via DevJourney MCP."
        )
        activeSessions[ticket.id] = session
        try? context.save()
        syncTicketStorage(for: ticket, project: project)

        let initialArtifactDate = latestArtifactDate(for: ticket)
        let initialClarifications = ticket.pendingClarificationCount

        runningTasks[ticket.id] = Task { [weak self] in
            guard let self else { return }
            await self.runExternalStage(
                ticket: ticket,
                project: project,
                client: client,
                prompt: prompt,
                session: session,
                initialArtifactDate: initialArtifactDate,
                initialClarifications: initialClarifications
            )
        }
    }

    func stopStage(for ticket: Ticket) {
        runningTasks[ticket.id]?.cancel()
        runningTasks.removeValue(forKey: ticket.id)

        if let session = activeSessions.removeValue(forKey: ticket.id) {
            session.addEvent(type: .failed, message: "Run stopped by user.")
            session.end()
        }

        ticket.setStatus(.ready)
        ticket.setHandoverState(.idle)
        try? context.save()
        syncTicketStorage(for: ticket)
    }

    func resumeStage(
        for ticket: Ticket,
        project: Project,
        mcpConnectionStatus: MCPConnectionStatusSnapshot = MCPConnectionStatusSnapshot(
            clientName: nil,
            lastSeenAt: nil,
            serverPID: nil
        ),
        claudeRegistrationStatus: ClaudeMCPRegistrationStatus = .init(mode: .notConfigured)
    ) {
        _ = reconcileClarifications(for: ticket, project: project)
        let unanswered = ticket.clarifications.filter { $0.answer == nil }
        guard unanswered.isEmpty else {
            ticket.setStatus(.clarify)
            try? context.save()
            syncTicketStorage(for: ticket, project: project)
            return
        }

        startStage(
            for: ticket,
            project: project,
            mcpConnectionStatus: mcpConnectionStatus,
            claudeRegistrationStatus: claudeRegistrationStatus
        )
    }

    @discardableResult
    func reconcileClarifications(for ticket: Ticket, project: Project) -> Int {
        let resolvedDuplicates = resolveRedundantClarifications(for: ticket)
        let recoveredReturned = recoverReturnedReviewClarifications(for: ticket, project: project)
        return resolvedDuplicates + recoveredReturned
    }

    @discardableResult
    func requestClarification(for ticket: Ticket, question: String) -> ClarificationItem {
        let item = ClarificationItem(
            ticketId: ticket.id,
            stage: ticket.stage,
            question: question
        )
        context.insert(item)
        ticket.clarifications.append(item)
        ticket.setStatus(.clarify)
        ticket.setHandoverState(.blocked, blockedReason: question)
        if let session = activeSessions[ticket.id] {
            session.addEvent(type: .clarificationRequested, message: question)
            session.addThought("Clarification requested: \(question)")
        }
        try? context.save()
        syncTicketStorage(for: ticket)
        return item
    }

    func answerClarification(_ item: ClarificationItem, for ticket: Ticket, response: String) {
        item.answer(response)
        _ = resolveRedundantClarifications(for: ticket)
        let hasPendingClarifications = ticket.pendingClarificationCount > 0
        ticket.setStatus(hasPendingClarifications ? .clarify : .ready)
        ticket.setHandoverState(hasPendingClarifications ? .blocked : .idle)
        try? context.save()
        syncTicketStorage(for: ticket)
    }

    func addOperatorInstruction(_ text: String, for ticket: Ticket) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let item = ClarificationItem(
            ticketId: ticket.id,
            stage: ticket.stage,
            question: "Operator instruction for \(ticket.stageEnum.displayName)"
        )
        item.answer(trimmed)
        context.insert(item)
        ticket.clarifications.append(item)
        if let session = activeSessions[ticket.id] {
            session.addEvent(type: .artifactPatched, message: "Operator instruction added for the next run.")
            session.addThought("Operator instruction: \(trimmed)")
        }
        try? context.save()
        syncTicketStorage(for: ticket)
    }

    func submitReviewDecision(
        for ticket: Ticket,
        approved: Bool,
        comment: String?
    ) -> HandoverGateResult? {
        let decision = ReviewResult(
            ticketId: ticket.id,
            stage: ticket.stage,
            approved: approved
        )
        if let comment, !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            decision.setComment(comment)
        }
        context.insert(decision)
        ticket.reviewResults.append(decision)

        if approved {
            let gateResult = requestHandover(for: ticket)
            if gateResult.passed {
                if ticket.stageEnum == .debug {
                    ticket.setStage(.complete)
                    ticket.setStatus(.complete)
                    ticket.setHandoverState(.complete)
                } else if let nextStage = ticket.stageEnum.nextStage() {
                    ticket.setStage(nextStage)
                    ticket.setStatus(.ready)
                    ticket.setHandoverState(.handedOff)
                }
            } else {
                ticket.setStatus(.clarify)
                ticket.setHandoverState(.blocked, blockedReason: gateResult.missingFields.joined(separator: ", "))
            }
            try? context.save()
            syncTicketStorage(for: ticket)
            return gateResult
        } else {
            let trimmedComment = comment?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let reviewInstruction: String
            if trimmedComment.isEmpty {
                reviewInstruction = "Review requested changes for this \(ticket.stageEnum.displayName) result. Please revise the work and continue the same stage."
            } else {
                reviewInstruction = trimmedComment
            }

            let clarification = ClarificationItem(
                ticketId: ticket.id,
                stage: ticket.stage,
                question: "Review requested changes"
            )
            clarification.answer(reviewInstruction)
            context.insert(clarification)
            ticket.clarifications.append(clarification)
            let resolvedDuplicates = resolveRedundantClarifications(for: ticket)
            ticket.setStatus(.ready)
            ticket.setHandoverState(.returned)
            if let session = activeSessions[ticket.id] {
                if resolvedDuplicates > 0, let answer = clarification.answer {
                    session.addEvent(type: .artifactPatched, message: "Reused an existing clarification answer for a repeated review request.")
                    session.addThought("Reused prior review clarification answer: \(answer)")
                } else {
                    session.addEvent(type: .artifactPatched, message: "Review feedback added for the next run.")
                    session.addThought("Review requested changes: \(reviewInstruction)")
                }
            }
            try? context.save()
            syncTicketStorage(for: ticket)
            return nil
        }
    }

    func requestHandover(for ticket: Ticket) -> HandoverGateResult {
        let unansweredQuestions = ticket.clarifications
            .filter { $0.stage == ticket.stage && $0.answer == nil }
            .map(\.question)

        var missingFields: [String] = []
        var score = ticket.stageScore

        switch ticket.stageEnum {
        case .planning:
            let spec = ticket.latestPlanningSpec
            if spec?.problem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                missingFields.append("problem")
            }
            if spec?.acceptanceCriteria.isEmpty != false {
                missingFields.append("acceptanceCriteria")
            }
            if spec?.definitionOfReady.isEmpty != false {
                missingFields.append("definitionOfReady")
            }
            score = spec?.planningScore ?? 0

        case .design:
            let spec = ticket.latestDesignSpec
            if spec?.appPlacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                missingFields.append("appPlacement")
            }
            if spec?.affectedScreens.isEmpty != false {
                missingFields.append("affectedScreens")
            }
            if spec?.statesMatrix.isEmpty != false {
                missingFields.append("statesMatrix")
            }
            if spec?.responsiveRules.isEmpty != false {
                missingFields.append("responsiveRules")
            }
            if spec?.accessibilityNotes.isEmpty != false {
                missingFields.append("accessibilityNotes")
            }
            score = spec?.designScore ?? 0

        case .dev:
            let execution = ticket.latestDevExecution
            if execution?.implementationNotes.isEmpty != false {
                missingFields.append("implementationNotes")
            }
            if execution?.changedFiles.isEmpty != false {
                missingFields.append("changedFiles")
            }
            if execution?.buildStatusEnum == .failed {
                missingFields.append("buildStatus")
            }
            score = execution?.changedFiles.isEmpty == false ? 100 : 0

        case .debug:
            let report = ticket.latestDebugReport
            if report?.testedScenarios.isEmpty != false {
                missingFields.append("testedScenarios")
            }
            if report?.releaseRecommendationEnum == .blocked {
                missingFields.append("releaseRecommendation")
            }
            score = report?.coverageScore ?? 0

        case .backlog, .complete:
            break
        }

        let passed = unansweredQuestions.isEmpty && missingFields.isEmpty && score >= 60
        return HandoverGateResult(
            stage: ticket.stage,
            passed: passed,
            missingFields: missingFields,
            blockingQuestions: unansweredQuestions,
            score: score
        )
    }

    func upsertPlanningSpec(for ticket: Ticket, input: PlanningSpecInput) {
        let spec = ticket.latestPlanningSpec ?? PlanningSpec(ticketId: ticket.id)
        if ticket.latestPlanningSpec == nil {
            context.insert(spec)
            ticket.planningSpecs.append(spec)
        }

        spec.problem = input.problem
        spec.scopeIn = input.scopeIn
        spec.scopeOut = input.scopeOut
        spec.acceptanceCriteria = input.acceptanceCriteria
        spec.dependencies = input.dependencies
        spec.assumptions = input.assumptions
        spec.risks = input.risks
        spec.subtasks = input.subtasks
        spec.definitionOfReady = input.definitionOfReady
        spec.summary = input.summary
        spec.planningScore = clampScore(input.planningScore ?? computePlanningScore(spec: spec))
        spec.updatedAt = Date()
    }

    func upsertDesignSpec(for ticket: Ticket, input: DesignSpecInput) {
        let spec = ticket.latestDesignSpec ?? DesignSpec(ticketId: ticket.id)
        if ticket.latestDesignSpec == nil {
            context.insert(spec)
            ticket.designSpecs.append(spec)
        }

        spec.appPlacement = input.appPlacement
        spec.affectedScreens = input.affectedScreens
        spec.userFlow = input.userFlow
        spec.components = input.components
        spec.microcopy = input.microcopy
        spec.statesMatrix = input.statesMatrix
        spec.responsiveRules = input.responsiveRules
        spec.accessibilityNotes = input.accessibilityNotes
        spec.figmaRefs = input.figmaRefs
        spec.summary = input.summary
        spec.designScore = clampScore(input.designScore ?? computeDesignScore(spec: spec))
        spec.updatedAt = Date()
    }

    func upsertDevExecution(for ticket: Ticket, input: DevExecutionInput) {
        let execution = ticket.latestDevExecution ?? DevExecution(ticketId: ticket.id)
        if ticket.latestDevExecution == nil {
            context.insert(execution)
            ticket.devExecutions.append(execution)
        }

        execution.branch = input.branch
        execution.commitList = input.commitList
        execution.changedFiles = input.changedFiles
        execution.previewURLs = input.previewURLs
        execution.implementationNotes = input.implementationNotes
        execution.buildStatus = input.buildStatus.rawValue
        execution.summary = input.summary
        execution.updatedAt = Date()
    }

    func upsertDebugReport(for ticket: Ticket, input: DebugReportInput) {
        let report = ticket.latestDebugReport ?? DebugReport(ticketId: ticket.id)
        if ticket.latestDebugReport == nil {
            context.insert(report)
            ticket.debugReports.append(report)
        }

        report.testedScenarios = input.testedScenarios
        report.failedScenarios = input.failedScenarios
        report.bugItems = input.bugItems
        report.severitySummary = input.severitySummary
        report.releaseRecommendation = input.releaseRecommendation.rawValue
        report.summary = input.summary
        report.coverageScore = clampScore(input.coverageScore ?? computeDebugScore(report: report))
        report.updatedAt = Date()
    }

    func ticketContext(for ticket: Ticket, project: Project) -> [String: Any] {
        [
            "ticket": [
                "id": ticket.id,
                "title": ticket.title,
                "description": ticket.ticketDescription,
                "stage": ticket.stage,
                "status": ticket.status,
                "handover_state": ticket.handoverState,
                "active_model": ticket.activeModel ?? "",
                "pending_clarifications": ticket.pendingClarificationCount
            ],
            "project": [
                "name": project.name,
                "type": project.projectType,
                "description": project.projectDescription,
                "folder": project.folderPath,
                "tech_stack": project.techStack,
                "screen_sizes": project.screenSizes,
                "responsive_behavior": project.responsiveBehavior,
                "mobile_platforms": project.normalizedMobilePlatforms
            ],
            "artifacts": [
                "planning": ticket.latestPlanningSpec?.summary ?? [],
                "design": ticket.latestDesignSpec?.summary ?? [],
                "dev": ticket.latestDevExecution?.summary ?? [],
                "debug": ticket.latestDebugReport?.summary ?? []
            ]
        ]
    }

    func resolvedProviderRuntime(
        for stage: Stage,
        project: Project
    ) -> (config: AIProviderConfig?, model: String?) {
        guard let config = resolveProviderConfig(for: stage, project: project) else {
            return (nil, nil)
        }
        return (config, resolveModel(for: stage, project: project, providerConfig: config))
    }

    private func externalPrompt(for ticket: Ticket, project: Project) -> String {
        let runNotes = externalRunNotes(for: ticket)
        guard let promptName = mcpPromptName(for: ticket.stageEnum),
              let template = MCPPromptTemplates.renderedPromptText(
                  name: promptName,
                  arguments: [
                    "ticket_id": ticket.id,
                    "run_notes": runNotes
                  ]
              ) else {
            return """
            Execute the \(ticket.stageEnum.displayName.lowercased()) stage for DevJourney ticket \(ticket.id).
            Use the DevJourney MCP tools to read ticket context, update the correct artifact, request clarification when blocked, and request handover before finishing.
            """
        }

        return template + """

        ---

        Runtime notes:
        - You are running from the project directory: \(project.folderPath)
        - Complete the stage in this single run.
        - Persist all workflow changes through DevJourney MCP tools before you finish.
        - During the Dev stage, you must make the actual project file changes through MCP file tools before submitting the Dev artifact. Do not stop at a plan or description of changes.
        - If the ticket asks for analysis, investigation, logging, or a plain-text findings handoff, do not block on missing source files or unspecified tech stack alone. Record those gaps as assumptions and risks, then produce the stage artifact from the available evidence.
        - Never repeat a clarification that already has an answer in the ticket context. Treat answered clarifications as authoritative operator instructions.
        - Even when the user wants a plain-text answer in DevJourney, you must still write the stage artifact through MCP so the board can review it.
        - End with a concise summary of what you updated.
        """
    }

    private func externalRunNotes(for ticket: Ticket) -> String {
        let answered = ticket.clarifications
            .filter { $0.stage == ticket.stage }
            .filter { ($0.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            .sorted { lhs, rhs in
                let left = lhs.answeredAt ?? .distantPast
                let right = rhs.answeredAt ?? .distantPast
                return left < right
            }

        guard !answered.isEmpty else { return "" }

        let items = answered.map { item in
            let question = item.question.trimmingCharacters(in: .whitespacesAndNewlines)
            let answer = (item.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return "- Q: \(question)\n  A: \(answer)"
        }

        return """
        Answered clarifications for this stage. These are authoritative user instructions and must be applied in this rerun:
        \(items.joined(separator: "\n"))
        """
    }

    @discardableResult
    func resolveRedundantClarifications(for ticket: Ticket) -> Int {
        let unanswered = ticket.clarifications.filter { $0.stage == ticket.stage && $0.answer == nil }
        guard !unanswered.isEmpty else { return 0 }

        let answeredReviewClarifications = ticket.clarifications.filter { item in
            item.stage == ticket.stage &&
            (item.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
            item.question.localizedCaseInsensitiveContains("Review requested changes")
        }

        guard !answeredReviewClarifications.isEmpty else { return 0 }

        var resolvedCount = 0
        for item in unanswered where item.question.localizedCaseInsensitiveContains("Review requested changes") {
            guard let reusable = answeredReviewClarifications.first(where: { candidate in
                reviewClarificationSimilarity(
                    lhs: item.question,
                    rhs: candidate.question
                ) >= 0.5
            }),
            let answer = reusable.answer,
            !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            item.answer(answer)
            resolvedCount += 1
        }

        if resolvedCount > 0 {
            let hasPendingClarifications = ticket.pendingClarificationCount > 0
            ticket.setStatus(hasPendingClarifications ? .clarify : .ready)
            if hasPendingClarifications {
                let latestPendingQuestion = ticket.clarifications
                    .last(where: { $0.stage == ticket.stage && $0.answer == nil })?
                    .question
                ticket.setHandoverState(.blocked, blockedReason: latestPendingQuestion)
            } else if ticket.handoverStateEnum == .returned {
                ticket.setHandoverState(.returned)
            } else {
                ticket.setHandoverState(.idle)
            }
            try? context.save()
            syncTicketStorage(for: ticket)
        }

        return resolvedCount
    }

    @discardableResult
    private func recoverReturnedReviewClarifications(for ticket: Ticket, project: Project) -> Int {
        let pendingReturnedReviewClarifications = ticket.clarifications.filter { item in
            item.stage == ticket.stage &&
            item.answer == nil &&
            item.question.localizedCaseInsensitiveContains("Review requested changes")
        }

        guard !pendingReturnedReviewClarifications.isEmpty else { return 0 }

        let latestRejectedReviewComment = ticket.reviewResults
            .filter { !$0.approved && $0.stage == ticket.stage }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { result -> String? in
                let trimmed = (result.reviewerComment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .first

        let latestAnsweredReviewInstruction = ticket.clarifications
            .filter {
                $0.stage == ticket.stage &&
                $0.question.localizedCaseInsensitiveContains("Review requested changes")
            }
            .sorted { ($0.answeredAt ?? .distantPast) > ($1.answeredAt ?? .distantPast) }
            .compactMap { item -> String? in
                let trimmed = (item.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            .first

        var recoveredCount = 0
        for item in pendingReturnedReviewClarifications {
            let inlineInstruction = item.question
                .components(separatedBy: ":")
                .dropFirst()
                .joined(separator: ":")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let recoveredInstruction =
                !inlineInstruction.isEmpty ? inlineInstruction :
                latestRejectedReviewComment ??
                latestAnsweredReviewInstruction

            guard let recoveredInstruction, !recoveredInstruction.isEmpty else {
                continue
            }

            item.answer(recoveredInstruction)
            recoveredCount += 1
        }

        guard recoveredCount > 0 else { return 0 }

        let hasPendingClarifications = ticket.pendingClarificationCount > 0
        ticket.setStatus(hasPendingClarifications ? .clarify : .ready)
        if hasPendingClarifications {
            let latestPendingQuestion = ticket.clarifications
                .last(where: { $0.stage == ticket.stage && $0.answer == nil })?
                .question
            ticket.setHandoverState(.blocked, blockedReason: latestPendingQuestion)
        } else {
            ticket.setHandoverState(.returned)
        }
        try? context.save()
        syncTicketStorage(for: ticket, project: project)
        return recoveredCount
    }

    private func reviewClarificationSimilarity(lhs: String, rhs: String) -> Double {
        let leftTokens = normalizedReviewTokens(from: lhs)
        let rightTokens = normalizedReviewTokens(from: rhs)

        guard !leftTokens.isEmpty, !rightTokens.isEmpty else { return 0 }

        let overlap = leftTokens.intersection(rightTokens).count
        let baseline = max(1, min(leftTokens.count, rightTokens.count))
        return Double(overlap) / Double(baseline)
    }

    private func normalizedReviewTokens(from value: String) -> Set<String> {
        let stripped = value
            .lowercased()
            .replacingOccurrences(of: "review requested changes:", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                token.count > 2 && ![
                    "review", "requested", "changes", "this", "stage", "result",
                    "please", "revise", "work", "continue", "auch", "und", "die",
                    "der", "das", "mit", "für", "the", "and", "only", "want"
                ].contains(token)
            }

        return Set(stripped)
    }

    private func latestArtifactDate(for ticket: Ticket) -> Date? {
        switch ticket.stageEnum {
        case .planning:
            return ticket.latestPlanningSpec?.updatedAt
        case .design:
            return ticket.latestDesignSpec?.updatedAt
        case .dev:
            return ticket.latestDevExecution?.updatedAt
        case .debug:
            return ticket.latestDebugReport?.updatedAt
        case .backlog, .complete:
            return nil
        }
    }

    private func runExternalStage(
        ticket: Ticket,
        project: Project,
        client: ExternalAgentClient,
        prompt: String,
        session: AgentSession,
        initialArtifactDate: Date?,
        initialClarifications: Int
    ) async {
        do {
            let result = try await externalRunnerService.run(
                client: client,
                projectDirectory: project.folderPath,
                prompt: prompt,
                onThought: { [weak session] thought in
                    guard let session else { return }
                    session.addThought(thought)
                    session.addEvent(type: .thoughtDelta, message: thought)
                },
                onAssistantDelta: { [weak session] delta in
                    guard let session else { return }
                    session.appendAssistantDelta(delta)
                }
            )

            guard !Task.isCancelled else { return }

            if !result.finalMessage.isEmpty, session.liveResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.appendAssistantDelta(result.finalMessage)
            }

            if result.terminationStatus == 0 {
                _ = projectService.getProjectTickets(projectId: project.id)
                finishExternalStageRun(
                    ticket: ticket,
                    session: session,
                    client: client,
                    initialArtifactDate: initialArtifactDate,
                    initialClarifications: initialClarifications
                )
            } else {
                let errorText = result.errorOutput.isEmpty
                    ? "\(client.displayName) exited with status \(result.terminationStatus)."
                    : result.errorOutput
                session.errorMessage = errorText
                session.addEvent(type: .failed, message: errorText)
                ticket.setStatus(.clarify)
                ticket.setHandoverState(.blocked, blockedReason: errorText)
            }

            session.end()
        } catch is CancellationError {
            session.addEvent(type: .failed, message: "Run cancelled.")
            ticket.setStatus(.ready)
            ticket.setHandoverState(.idle)
            session.end()
        } catch {
            session.errorMessage = error.localizedDescription
            session.addEvent(type: .failed, message: error.localizedDescription)
            ticket.setStatus(.clarify)
            ticket.setHandoverState(.blocked, blockedReason: error.localizedDescription)
            session.end()
        }

        runningTasks.removeValue(forKey: ticket.id)
        activeSessions.removeValue(forKey: ticket.id)
        try? context.save()
        syncTicketStorage(for: ticket, project: project)
    }

    private func finishExternalStageRun(
        ticket: Ticket,
        session: AgentSession,
        client: ExternalAgentClient,
        initialArtifactDate: Date?,
        initialClarifications: Int
    ) {
        var artifactChanged = latestArtifactDate(for: ticket) != initialArtifactDate
        let clarificationChanged = ticket.pendingClarificationCount != initialClarifications

        if !artifactChanged,
           ticket.pendingClarificationCount == 0,
           synthesizeArtifactFromTranscriptIfNeeded(ticket: ticket, session: session) {
            artifactChanged = true
        }

        let gate = requestHandover(for: ticket)

        if gate.passed {
            ticket.setStatus(.done)
            ticket.setHandoverState(.readyForReview)
            session.addEvent(type: .artifactPatched, message: "Updated \(ticket.stageEnum.displayName) artifacts.")
            session.addEvent(type: .completed, message: "Stage output ready for review.")
            return
        }

        if ticket.pendingClarificationCount > 0 {
            let pendingQuestion = ticket.clarifications
                .last(where: { $0.answer == nil })?
                .question ?? gate.blockingQuestions.first
                ?? "Clarification required before continuing."
            ticket.setStatus(.clarify)
            ticket.setHandoverState(.blocked, blockedReason: pendingQuestion)
            session.addEvent(type: .clarificationRequested, message: pendingQuestion)
            return
        }

        if artifactChanged || clarificationChanged {
            let missing = gate.missingFields.joined(separator: ", ")
            let reason = missing.isEmpty
                ? "\(client.displayName) completed the run, but the stage is still incomplete."
                : "Missing handover fields: \(missing)"
            ticket.setStatus(.clarify)
            ticket.setHandoverState(.blocked, blockedReason: reason)
            session.addEvent(type: .artifactPatched, message: "External run updated the ticket, but review is still blocked.")
            return
        }

        let reason = "\(client.displayName) completed the run without writing DevJourney artifacts. Try again or review the client transcript."
        ticket.setStatus(.clarify)
        ticket.setHandoverState(.blocked, blockedReason: reason)
        session.addEvent(type: .failed, message: reason)
    }

    private func synthesizeArtifactFromTranscriptIfNeeded(ticket: Ticket, session: AgentSession) -> Bool {
        let transcript = session.liveResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return false }

        let summary = fallbackSummary(from: transcript)
        guard !summary.isEmpty else { return false }

        switch ticket.stageEnum {
        case .planning:
            upsertPlanningSpec(
                for: ticket,
                input: PlanningSpecInput(
                    problem: ticket.ticketDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? ticket.title
                        : ticket.ticketDescription,
                    scopeIn: Array(summary.prefix(3)),
                    scopeOut: [],
                    acceptanceCriteria: summary,
                    dependencies: [],
                    assumptions: ["Synthesized from external agent transcript."],
                    risks: [],
                    subtasks: [],
                    definitionOfReady: ["Review the transcript summary and approve or request changes."],
                    summary: summary,
                    planningScore: 72
                )
            )
            session.addEvent(type: .artifactPatched, message: "Synthesized planning artifact from transcript.")
            return true

        case .design:
            upsertDesignSpec(
                for: ticket,
                input: DesignSpecInput(
                    appPlacement: summary.first ?? ticket.title,
                    affectedScreens: [],
                    userFlow: summary,
                    components: [],
                    microcopy: [],
                    statesMatrix: [],
                    responsiveRules: ["Review transcript for detailed responsive requirements."],
                    accessibilityNotes: [],
                    figmaRefs: [],
                    summary: summary,
                    designScore: 68
                )
            )
            session.addEvent(type: .artifactPatched, message: "Synthesized design artifact from transcript.")
            return true

        case .dev:
            upsertDevExecution(
                for: ticket,
                input: DevExecutionInput(
                    branch: "",
                    commitList: [],
                    changedFiles: [],
                    previewURLs: [],
                    implementationNotes: summary,
                    buildStatus: .pending,
                    summary: summary,
                    commitMessage: nil
                )
            )
            session.addEvent(type: .artifactPatched, message: "Synthesized development artifact from transcript.")
            return true

        case .debug:
            upsertDebugReport(
                for: ticket,
                input: DebugReportInput(
                    testedScenarios: [],
                    failedScenarios: [],
                    bugItems: summary,
                    severitySummary: summary.first ?? "Captured from external agent transcript.",
                    releaseRecommendation: .pending,
                    summary: summary,
                    coverageScore: 65
                )
            )
            session.addEvent(type: .artifactPatched, message: "Synthesized debug artifact from transcript.")
            return true

        case .backlog, .complete:
            return false
        }
    }

    private func runStage(
        request: AgentExecutionRequest,
        ticket: Ticket,
        project: Project,
        providerConfig: AIProviderConfig,
        runtimeConfiguration: ResolvedProviderConfiguration,
        apiKey: String,
        session: AgentSession
    ) async {
        var streamedCharacters = 0

        do {
            let response = try await providerRegistry.execute(
                request: request,
                configuration: runtimeConfiguration,
                apiKey: apiKey
            ) { [weak session] delta in
                guard let session else { return }
                session.appendAssistantDelta(delta)
                streamedCharacters += delta.count
                if streamedCharacters >= 240 {
                    session.addEvent(type: .tokenDelta, message: "Streamed \(session.liveResponse.count) characters.")
                    streamedCharacters = 0
                }
            }

            guard !Task.isCancelled else { return }

            processResponse(
                response,
                for: ticket,
                project: project,
                providerConfig: providerConfig,
                session: session
            )
        } catch is CancellationError {
            session.addEvent(type: .failed, message: "Run cancelled.")
            ticket.setStatus(.ready)
            ticket.setHandoverState(.idle)
            session.end()
        } catch {
            session.errorMessage = error.localizedDescription
            session.addEvent(type: .failed, message: error.localizedDescription)
            ticket.setStatus(.clarify)
            ticket.setHandoverState(.blocked, blockedReason: error.localizedDescription)
            session.end()
        }

        runningTasks.removeValue(forKey: ticket.id)
        activeSessions.removeValue(forKey: ticket.id)
        try? context.save()
        syncTicketStorage(for: ticket, project: project)
    }

    private func processResponse(
        _ response: String,
        for ticket: Ticket,
        project: Project,
        providerConfig: AIProviderConfig,
        session: AgentSession
    ) {
        let normalized = response.trimmingCharacters(in: .whitespacesAndNewlines)

        switch ticket.stageEnum {
        case .planning:
            let parsed = parsePlanningResponse(from: normalized)
            applyCommonResult(parsed.thoughts, parsed.summary, parsed.filesChanged, to: session)
            upsertPlanningSpec(for: ticket, input: parsed.artifact)
            finishRun(
                ticket: ticket,
                project: project,
                session: session,
                clarificationQuestion: parsed.clarificationQuestion,
                commitMessage: nil
            )

        case .design:
            let parsed = parseDesignResponse(from: normalized)
            applyCommonResult(parsed.thoughts, parsed.summary, parsed.filesChanged, to: session)
            upsertDesignSpec(for: ticket, input: parsed.artifact)
            finishRun(
                ticket: ticket,
                project: project,
                session: session,
                clarificationQuestion: parsed.clarificationQuestion,
                commitMessage: nil
            )

        case .dev:
            let parsed = parseDevResponse(from: normalized)
            applyCommonResult(parsed.thoughts, parsed.summary, parsed.filesChanged, to: session)
            upsertDevExecution(for: ticket, input: parsed.artifact)
            finishRun(
                ticket: ticket,
                project: project,
                session: session,
                clarificationQuestion: parsed.clarificationQuestion,
                commitMessage: parsed.artifact.commitMessage
            )

        case .debug:
            let parsed = parseDebugResponse(from: normalized)
            applyCommonResult(parsed.thoughts, parsed.summary, parsed.filesChanged, to: session)
            upsertDebugReport(for: ticket, input: parsed.artifact)
            finishRun(
                ticket: ticket,
                project: project,
                session: session,
                clarificationQuestion: parsed.clarificationQuestion,
                commitMessage: nil
            )

        case .backlog, .complete:
            session.addThought("No runtime configured for \(ticket.stageEnum.displayName).")
            session.end()
            ticket.setStatus(.ready)
            ticket.setHandoverState(.idle)
        }

        providerConfig.touch()
    }

    private func finishRun(
        ticket: Ticket,
        project: Project,
        session: AgentSession,
        clarificationQuestion: String?,
        commitMessage: String?
    ) {
        session.addEvent(type: .artifactPatched, message: "Updated \(ticket.stageEnum.displayName) artifacts.")

        if let clarificationQuestion, !clarificationQuestion.isEmpty {
            _ = requestClarification(for: ticket, question: clarificationQuestion)
            session.addThought("Clarification required before handover.")
        } else {
            ticket.setStatus(.done)
            ticket.setHandoverState(.readyForReview)
            session.addEvent(type: .completed, message: "Stage output ready for review.")
        }

        session.end()

        if let execution = ticket.latestDevExecution,
           !execution.changedFiles.isEmpty,
           ticket.stageEnum == .dev || ticket.stageEnum == .debug {
            Task {
                let commitFiles = execution.changedFiles.map(\.path)
                let message = commitMessage ?? "[\(ticket.stageEnum.displayName)] \(ticket.title)"
                let result = await gitHubService.createCommit(
                    path: URL(fileURLWithPath: project.folderPath),
                    message: message,
                    files: commitFiles
                )
                if result.success {
                    session.commitCount += 1
                    if let hash = result.commitHash {
                        execution.commitList.append(hash)
                    }
                    try? context.save()
                }
            }
        }
    }

    private func applyCommonResult(
        _ thoughts: [String],
        _ summary: [String],
        _ filesChanged: [FileChange],
        to session: AgentSession
    ) {
        for thought in thoughts {
            session.addThought(thought)
            session.addEvent(type: .thoughtDelta, message: thought)
        }
        session.resultSummary = summary
        session.filesChanged = filesChanged
    }

    private func resolveProviderConfig(for stage: Stage, project: Project) -> AIProviderConfig? {
        if let configId = project.providerConfigId(for: stage),
           let config = project.providerConfigs.first(where: { $0.id == configId && $0.enabled }) {
            return config
        }

        return project.providerConfigs.first(where: { $0.kindEnum == .anthropic && $0.enabled })
            ?? project.providerConfigs.first(where: \.enabled)
    }

    private func resolveModel(for stage: Stage, project: Project, providerConfig: AIProviderConfig) -> String {
        project.modelOverride(for: stage) ?? providerConfig.defaultModel
    }

    private func agent(for stage: Stage) -> StageAgent {
        switch stage {
        case .planning:
            return PlanningAgent()
        case .design:
            return DesignAgent()
        case .dev:
            return DevAgent()
        case .debug:
            return DebugAgent()
        case .backlog, .complete:
            return PlanningAgent()
        }
    }

    func syncTicketStorage(for ticket: Ticket, project: Project? = nil) {
        let resolvedProject = project
            ?? projectService.loadProjects().first(where: { $0.id == ticket.projectId })
        guard let resolvedProject else { return }
        try? localTicketStore.syncTicket(ticket, project: resolvedProject)
    }

    private func clampScore(_ value: Double) -> Double {
        min(100, max(0, value))
    }

    private func computePlanningScore(spec: PlanningSpec) -> Double {
        let checkpoints = [
            !spec.problem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !spec.acceptanceCriteria.isEmpty,
            !spec.definitionOfReady.isEmpty,
            !spec.subtasks.isEmpty,
            !spec.risks.isEmpty,
            !spec.scopeIn.isEmpty
        ]
        return Double(checkpoints.filter { $0 }.count) / Double(checkpoints.count) * 100
    }

    private func computeDesignScore(spec: DesignSpec) -> Double {
        let checkpoints = [
            !spec.appPlacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !spec.affectedScreens.isEmpty,
            !spec.statesMatrix.isEmpty,
            !spec.responsiveRules.isEmpty,
            !spec.accessibilityNotes.isEmpty,
            !spec.components.isEmpty
        ]
        return Double(checkpoints.filter { $0 }.count) / Double(checkpoints.count) * 100
    }

    private func computeDebugScore(report: DebugReport) -> Double {
        let checkpoints = [
            !report.testedScenarios.isEmpty,
            !report.summary.isEmpty,
            report.releaseRecommendationEnum != .pending
        ]
        return Double(checkpoints.filter { $0 }.count) / Double(checkpoints.count) * 100
    }
}

private struct PlanningArtifactPayload: Decodable {
    var problem: String?
    var scopeIn: [String]?
    var scopeOut: [String]?
    var acceptanceCriteria: [String]?
    var dependencies: [String]?
    var assumptions: [String]?
    var risks: [String]?
    var subtasks: [String]?
    var definitionOfReady: [String]?
    var planningScore: Double?
}

private struct DesignArtifactPayload: Decodable {
    var appPlacement: String?
    var affectedScreens: [String]?
    var userFlow: [String]?
    var components: [String]?
    var microcopy: [String]?
    var statesMatrix: [String]?
    var responsiveRules: [String]?
    var accessibilityNotes: [String]?
    var figmaRefs: [String]?
    var designScore: Double?
}

private struct DevArtifactPayload: Decodable {
    var branch: String?
    var commitList: [String]?
    var filesChanged: [FileChange]?
    var previewURLs: [String]?
    var implementationNotes: [String]?
    var buildStatus: String?
    var commitMessage: String?
}

private struct DebugArtifactPayload: Decodable {
    var testedScenarios: [String]?
    var failedScenarios: [String]?
    var bugItems: [String]?
    var severitySummary: String?
    var releaseRecommendation: String?
    var coverageScore: Double?
}

private struct PlanningResponseEnvelope: Decodable {
    var thoughts: [String]?
    var summary: [String]?
    var clarificationQuestion: String?
    var artifact: PlanningArtifactPayload?
    var filesChanged: [FileChange]?
}

private struct DesignResponseEnvelope: Decodable {
    var thoughts: [String]?
    var summary: [String]?
    var clarificationQuestion: String?
    var artifact: DesignArtifactPayload?
    var filesChanged: [FileChange]?
}

private struct DevResponseEnvelope: Decodable {
    var thoughts: [String]?
    var summary: [String]?
    var clarificationQuestion: String?
    var artifact: DevArtifactPayload?
    var filesChanged: [FileChange]?
}

private struct DebugResponseEnvelope: Decodable {
    var thoughts: [String]?
    var summary: [String]?
    var clarificationQuestion: String?
    var artifact: DebugArtifactPayload?
    var filesChanged: [FileChange]?
}

private extension TicketWorkflowService {
    func parsePlanningResponse(from response: String) -> (
        thoughts: [String],
        summary: [String],
        clarificationQuestion: String?,
        filesChanged: [FileChange],
        artifact: PlanningSpecInput
    ) {
        if let parsed = decodeEnvelope(PlanningResponseEnvelope.self, from: response) {
            return (
                thoughts: parsed.thoughts ?? [],
                summary: parsed.summary ?? fallbackSummary(from: response),
                clarificationQuestion: parsed.clarificationQuestion,
                filesChanged: parsed.filesChanged ?? [],
                artifact: PlanningSpecInput(
                    problem: parsed.artifact?.problem ?? "",
                    scopeIn: parsed.artifact?.scopeIn ?? [],
                    scopeOut: parsed.artifact?.scopeOut ?? [],
                    acceptanceCriteria: parsed.artifact?.acceptanceCriteria ?? [],
                    dependencies: parsed.artifact?.dependencies ?? [],
                    assumptions: parsed.artifact?.assumptions ?? [],
                    risks: parsed.artifact?.risks ?? [],
                    subtasks: parsed.artifact?.subtasks ?? [],
                    definitionOfReady: parsed.artifact?.definitionOfReady ?? [],
                    summary: parsed.summary ?? fallbackSummary(from: response),
                    planningScore: parsed.artifact?.planningScore
                )
            )
        }

        return (
            thoughts: [],
            summary: fallbackSummary(from: response),
            clarificationQuestion: nil,
            filesChanged: [],
            artifact: PlanningSpecInput(
                problem: "",
                scopeIn: [],
                scopeOut: [],
                acceptanceCriteria: [],
                dependencies: [],
                assumptions: [],
                risks: [],
                subtasks: [],
                definitionOfReady: [],
                summary: fallbackSummary(from: response),
                planningScore: nil
            )
        )
    }

    func parseDesignResponse(from response: String) -> (
        thoughts: [String],
        summary: [String],
        clarificationQuestion: String?,
        filesChanged: [FileChange],
        artifact: DesignSpecInput
    ) {
        if let parsed = decodeEnvelope(DesignResponseEnvelope.self, from: response) {
            return (
                thoughts: parsed.thoughts ?? [],
                summary: parsed.summary ?? fallbackSummary(from: response),
                clarificationQuestion: parsed.clarificationQuestion,
                filesChanged: parsed.filesChanged ?? [],
                artifact: DesignSpecInput(
                    appPlacement: parsed.artifact?.appPlacement ?? "",
                    affectedScreens: parsed.artifact?.affectedScreens ?? [],
                    userFlow: parsed.artifact?.userFlow ?? [],
                    components: parsed.artifact?.components ?? [],
                    microcopy: parsed.artifact?.microcopy ?? [],
                    statesMatrix: parsed.artifact?.statesMatrix ?? [],
                    responsiveRules: parsed.artifact?.responsiveRules ?? [],
                    accessibilityNotes: parsed.artifact?.accessibilityNotes ?? [],
                    figmaRefs: parsed.artifact?.figmaRefs ?? [],
                    summary: parsed.summary ?? fallbackSummary(from: response),
                    designScore: parsed.artifact?.designScore
                )
            )
        }

        return (
            thoughts: [],
            summary: fallbackSummary(from: response),
            clarificationQuestion: nil,
            filesChanged: [],
            artifact: DesignSpecInput(
                appPlacement: "",
                affectedScreens: [],
                userFlow: [],
                components: [],
                microcopy: [],
                statesMatrix: [],
                responsiveRules: [],
                accessibilityNotes: [],
                figmaRefs: [],
                summary: fallbackSummary(from: response),
                designScore: nil
            )
        )
    }

    func parseDevResponse(from response: String) -> (
        thoughts: [String],
        summary: [String],
        clarificationQuestion: String?,
        filesChanged: [FileChange],
        artifact: DevExecutionInput
    ) {
        if let parsed = decodeEnvelope(DevResponseEnvelope.self, from: response) {
            let files = parsed.artifact?.filesChanged ?? parsed.filesChanged ?? []
            return (
                thoughts: parsed.thoughts ?? [],
                summary: parsed.summary ?? fallbackSummary(from: response),
                clarificationQuestion: parsed.clarificationQuestion,
                filesChanged: files,
                artifact: DevExecutionInput(
                    branch: parsed.artifact?.branch ?? "",
                    commitList: parsed.artifact?.commitList ?? [],
                    changedFiles: files,
                    previewURLs: parsed.artifact?.previewURLs ?? [],
                    implementationNotes: parsed.artifact?.implementationNotes ?? [],
                    buildStatus: BuildStatus(rawValue: parsed.artifact?.buildStatus ?? "") ?? .pending,
                    summary: parsed.summary ?? fallbackSummary(from: response),
                    commitMessage: parsed.artifact?.commitMessage
                )
            )
        }

        return (
            thoughts: [],
            summary: fallbackSummary(from: response),
            clarificationQuestion: nil,
            filesChanged: [],
            artifact: DevExecutionInput(
                branch: "",
                commitList: [],
                changedFiles: [],
                previewURLs: [],
                implementationNotes: fallbackSummary(from: response),
                buildStatus: .pending,
                summary: fallbackSummary(from: response),
                commitMessage: nil
            )
        )
    }

    func parseDebugResponse(from response: String) -> (
        thoughts: [String],
        summary: [String],
        clarificationQuestion: String?,
        filesChanged: [FileChange],
        artifact: DebugReportInput
    ) {
        if let parsed = decodeEnvelope(DebugResponseEnvelope.self, from: response) {
            return (
                thoughts: parsed.thoughts ?? [],
                summary: parsed.summary ?? fallbackSummary(from: response),
                clarificationQuestion: parsed.clarificationQuestion,
                filesChanged: parsed.filesChanged ?? [],
                artifact: DebugReportInput(
                    testedScenarios: parsed.artifact?.testedScenarios ?? [],
                    failedScenarios: parsed.artifact?.failedScenarios ?? [],
                    bugItems: parsed.artifact?.bugItems ?? [],
                    severitySummary: parsed.artifact?.severitySummary ?? "",
                    releaseRecommendation: ReleaseRecommendation(rawValue: parsed.artifact?.releaseRecommendation ?? "") ?? .pending,
                    summary: parsed.summary ?? fallbackSummary(from: response),
                    coverageScore: parsed.artifact?.coverageScore
                )
            )
        }

        return (
            thoughts: [],
            summary: fallbackSummary(from: response),
            clarificationQuestion: nil,
            filesChanged: [],
            artifact: DebugReportInput(
                testedScenarios: [],
                failedScenarios: [],
                bugItems: [],
                severitySummary: "",
                releaseRecommendation: .pending,
                summary: fallbackSummary(from: response),
                coverageScore: nil
            )
        )
    }

    func decodeEnvelope<T: Decodable>(_ type: T.Type, from response: String) -> T? {
        guard let jsonString = extractJSONObject(from: response),
              let data = jsonString.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(type, from: data)
    }

    func extractJSONObject(from response: String) -> String? {
        if let start = response.range(of: "```json")?.upperBound,
           let end = response.range(of: "```", range: start..<response.endIndex)?.lowerBound {
            return String(response[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let firstBrace = response.firstIndex(of: "{"),
           let lastBrace = response.lastIndex(of: "}") {
            return String(response[firstBrace...lastBrace])
        }

        return nil
    }

    func fallbackSummary(from response: String) -> [String] {
        response
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(8)
            .map { line in
                if line.hasPrefix("- ") {
                    return String(line.dropFirst(2))
                }
                return line
            }
    }
}
