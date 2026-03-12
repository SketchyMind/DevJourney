import XCTest
import SwiftData
@testable import DevJourney

@MainActor
final class TicketWorkflowServiceTests: XCTestCase {

    func testStartStageFallsBackToExternalRunnerWhenProviderKeyIsMissing() async throws {
        let services = try TestSupport.makeServices()
        let project = TestSupport.seedProject(projectService: services.projectService)
        let ticket = TestSupport.seedTicket(projectService: services.projectService, project: project, stage: .planning)

        services.workflowService.upsertPlanningSpec(
            for: ticket,
            input: PlanningSpecInput(
                problem: "Plan the ticket externally",
                scopeIn: ["Planning"],
                scopeOut: [],
                acceptanceCriteria: ["Artifact exists"],
                dependencies: [],
                assumptions: [],
                risks: [],
                subtasks: ["Run external agent"],
                definitionOfReady: ["Ready for design"],
                summary: ["Existing plan"],
                planningScore: 82
            )
        )

        let mockRunner = MockExternalAgentRunnerService()
        let workflow = TicketWorkflowService(
            modelContainer: services.container,
            projectService: services.projectService,
            gitHubService: services.gitHubService,
            localTicketStore: services.localTicketStore,
            externalRunnerService: mockRunner
        )

        workflow.startStage(
            for: ticket,
            project: project,
            mcpConnectionStatus: MCPConnectionStatusSnapshot(
                clientName: "codex-mcp-client",
                lastSeenAt: Date(),
                serverPID: 1
            ),
            claudeRegistrationStatus: .init(mode: .configuredLocal(command: "/tmp/devjourney-mcp"))
        )

        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRunner.runCalls.count, 1)
        XCTAssertEqual(mockRunner.runCalls.first?.client, .codex)
        XCTAssertEqual(ticket.statusEnum, .done)
        XCTAssertEqual(ticket.handoverStateEnum, .readyForReview)
        XCTAssertEqual(ticket.activeProviderConfigId, ExternalAgentClient.codex.providerDisplayName)
        XCTAssertEqual(ticket.activeModel, ExternalAgentClient.codex.modelDisplayName)
    }

    func testExternalPlainTextPlanningResponseSynthesizesReviewableArtifact() async throws {
        let services = try TestSupport.makeServices()
        let project = TestSupport.seedProject(projectService: services.projectService)
        let ticket = TestSupport.seedTicket(projectService: services.projectService, project: project, stage: .planning)

        let mockRunner = MockExternalAgentRunnerService()
        mockRunner.result = ExternalAgentRunResult(
            client: .claudeCode,
            terminationStatus: 0,
            finalMessage: """
            Investigated the MCP connection path from the current Xcode build.
            The app is launching the stable user-scoped DevJourney MCP helper.
            Remaining work is to expose the raw transcript and persist ticket state across relaunches.
            """,
            errorOutput: ""
        )

        let workflow = TicketWorkflowService(
            modelContainer: services.container,
            projectService: services.projectService,
            gitHubService: services.gitHubService,
            localTicketStore: services.localTicketStore,
            externalRunnerService: mockRunner
        )

        workflow.startStage(
            for: ticket,
            project: project,
            mcpConnectionStatus: MCPConnectionStatusSnapshot(
                clientName: "claude-code",
                lastSeenAt: Date(),
                serverPID: 1
            ),
            claudeRegistrationStatus: .init(mode: .configuredLocal(command: "/tmp/devjourney-mcp"))
        )

        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(ticket.statusEnum, .done)
        XCTAssertEqual(ticket.handoverStateEnum, .readyForReview)
        XCTAssertEqual(ticket.latestPlanningSpec?.summary.isEmpty, false)
        XCTAssertEqual(ticket.latestPlanningSpec?.problem.isEmpty, false)
    }

    func testExternalRerunPromptIncludesAnsweredClarifications() async throws {
        let services = try TestSupport.makeServices()
        let project = TestSupport.seedProject(projectService: services.projectService)
        let ticket = TestSupport.seedTicket(projectService: services.projectService, project: project, stage: .planning)

        let clarification = services.workflowService.requestClarification(
            for: ticket,
            question: "What should the final deliverable look like?"
        )
        services.workflowService.answerClarification(
            clarification,
            for: ticket,
            response: "Return the findings as plain text in the ticket and treat this Xcode workspace as the source of truth."
        )

        let mockRunner = MockExternalAgentRunnerService()
        let workflow = TicketWorkflowService(
            modelContainer: services.container,
            projectService: services.projectService,
            gitHubService: services.gitHubService,
            localTicketStore: services.localTicketStore,
            externalRunnerService: mockRunner
        )

        workflow.startStage(
            for: ticket,
            project: project,
            mcpConnectionStatus: MCPConnectionStatusSnapshot(
                clientName: "claude-code",
                lastSeenAt: Date(),
                serverPID: 1
            ),
            claudeRegistrationStatus: .init(mode: .configuredLocal(command: "/tmp/devjourney-mcp"))
        )

        try await Task.sleep(nanoseconds: 300_000_000)

        let prompt = try XCTUnwrap(mockRunner.runCalls.first?.prompt)
        XCTAssertTrue(prompt.contains("Answered clarifications for this stage"))
        XCTAssertTrue(prompt.contains("What should the final deliverable look like?"))
        XCTAssertTrue(prompt.contains("Return the findings as plain text in the ticket"))
    }

    func testPlanningHandoverFailsWithoutArtifactAndPassesWhenArtifactIsComplete() throws {
        let services = try TestSupport.makeServices()
        let project = TestSupport.seedProject(projectService: services.projectService)
        let ticket = TestSupport.seedTicket(projectService: services.projectService, project: project, stage: .planning)

        let initialGate = services.workflowService.requestHandover(for: ticket)
        XCTAssertFalse(initialGate.passed)
        XCTAssertTrue(initialGate.missingFields.contains("problem"))
        XCTAssertTrue(initialGate.missingFields.contains("acceptanceCriteria"))
        XCTAssertTrue(initialGate.missingFields.contains("definitionOfReady"))

        services.workflowService.upsertPlanningSpec(
            for: ticket,
            input: PlanningSpecInput(
                problem: "Implement the provider runtime",
                scopeIn: ["Runtime", "Provider settings"],
                scopeOut: ["Analytics"],
                acceptanceCriteria: ["Providers can be selected", "Artifacts are persisted"],
                dependencies: ["SwiftData schema migration"],
                assumptions: ["The project runs on macOS only"],
                risks: ["Prompt schema drift"],
                subtasks: ["Seed providers", "Persist stage defaults"],
                definitionOfReady: ["A configured provider exists", "API key is available"],
                summary: ["Runtime plan is ready"],
                planningScore: 84
            )
        )

        let gate = services.workflowService.requestHandover(for: ticket)
        XCTAssertTrue(gate.passed)
        XCTAssertEqual(gate.missingFields, [])
        XCTAssertEqual(gate.score, 84)
    }

    func testApprovedPlanningReviewMovesTicketToDesign() throws {
        let services = try TestSupport.makeServices()
        let project = TestSupport.seedProject(projectService: services.projectService)
        let ticket = TestSupport.seedTicket(projectService: services.projectService, project: project, stage: .planning)

        services.workflowService.upsertPlanningSpec(
            for: ticket,
            input: PlanningSpecInput(
                problem: "Plan the ticket",
                scopeIn: ["App runtime"],
                scopeOut: [],
                acceptanceCriteria: ["A complete artifact exists"],
                dependencies: [],
                assumptions: [],
                risks: ["None"],
                subtasks: ["Review plan"],
                definitionOfReady: ["Ready"],
                summary: ["Planning complete"],
                planningScore: 90
            )
        )

        let result = services.workflowService.submitReviewDecision(for: ticket, approved: true, comment: "Looks good")

        XCTAssertTrue(try XCTUnwrap(result).passed)
        XCTAssertEqual(ticket.stageEnum, .design)
        XCTAssertEqual(ticket.statusEnum, .ready)
        XCTAssertEqual(ticket.handoverStateEnum, .handedOff)
    }

    func testRejectedReviewReturnsTicketWithoutChangingStage() throws {
        let services = try TestSupport.makeServices()
        let project = TestSupport.seedProject(projectService: services.projectService)
        let ticket = TestSupport.seedTicket(projectService: services.projectService, project: project, stage: .dev)

        let result = services.workflowService.submitReviewDecision(for: ticket, approved: false, comment: "Needs changes")

        XCTAssertNil(result)
        XCTAssertEqual(ticket.stageEnum, .dev)
        XCTAssertEqual(ticket.statusEnum, .ready)
        XCTAssertEqual(ticket.handoverStateEnum, .returned)
        XCTAssertEqual(ticket.pendingClarificationCount, 0)
        XCTAssertNil(ticket.blockedReason)
        XCTAssertEqual(ticket.clarifications.last?.question, "Review requested changes")
        XCTAssertEqual(ticket.clarifications.last?.answer, "Needs changes")
    }

    func testRepeatedReviewChangeReusesPriorAnsweredClarification() throws {
        let services = try TestSupport.makeServices()
        let project = TestSupport.seedProject(projectService: services.projectService)
        let ticket = TestSupport.seedTicket(projectService: services.projectService, project: project, stage: .planning)

        let first = services.workflowService.submitReviewDecision(
            for: ticket,
            approved: false,
            comment: "Include OpenAI and Google agent SDK support in the plan"
        )
        XCTAssertNil(first)
        let second = services.workflowService.submitReviewDecision(
            for: ticket,
            approved: false,
            comment: "Add OpenAI and Gemini agent SDK support too"
        )
        XCTAssertNil(second)

        let latestClarification = try XCTUnwrap(ticket.clarifications.last)
        XCTAssertEqual(
            latestClarification.answer,
            "Add OpenAI and Gemini agent SDK support too"
        )
        XCTAssertEqual(ticket.pendingClarificationCount, 0)
        XCTAssertEqual(ticket.statusEnum, .ready)
        XCTAssertEqual(ticket.handoverStateEnum, .returned)
    }

    func testResumeStageRecoversLegacyReturnedReviewClarificationAndUsesExternalRunner() async throws {
        let services = try TestSupport.makeServices()
        let project = TestSupport.seedProject(projectService: services.projectService)
        let ticket = TestSupport.seedTicket(projectService: services.projectService, project: project, stage: .planning)

        let staleReviewClarification = ClarificationItem(
            ticketId: ticket.id,
            stage: ticket.stage,
            question: "Review requested changes: i want the app design to be apple's liquid glass design"
        )
        services.container.mainContext.insert(staleReviewClarification)
        ticket.clarifications.append(staleReviewClarification)
        ticket.setStatus(.clarify)
        ticket.setHandoverState(.returned, blockedReason: staleReviewClarification.question)

        let mockRunner = MockExternalAgentRunnerService()
        let workflow = TicketWorkflowService(
            modelContainer: services.container,
            projectService: services.projectService,
            gitHubService: services.gitHubService,
            localTicketStore: services.localTicketStore,
            externalRunnerService: mockRunner
        )

        workflow.resumeStage(
            for: ticket,
            project: project,
            mcpConnectionStatus: MCPConnectionStatusSnapshot(
                clientName: "claude-code",
                lastSeenAt: Date(),
                serverPID: 1
            ),
            claudeRegistrationStatus: .init(mode: .configuredLocal(command: "/tmp/devjourney-mcp"))
        )

        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(mockRunner.runCalls.count, 1)
        XCTAssertEqual(
            staleReviewClarification.answer,
            "i want the app design to be apple's liquid glass design"
        )
        XCTAssertEqual(ticket.pendingClarificationCount, 0)
        XCTAssertEqual(ticket.statusEnum, .done)
        XCTAssertEqual(ticket.handoverStateEnum, .readyForReview)
    }

    func testDebugApprovalCompletesTicket() throws {
        let services = try TestSupport.makeServices()
        let project = TestSupport.seedProject(projectService: services.projectService)
        let ticket = TestSupport.seedTicket(projectService: services.projectService, project: project, stage: .debug)

        services.workflowService.upsertDebugReport(
            for: ticket,
            input: DebugReportInput(
                testedScenarios: ["Provider selection", "Review flow"],
                failedScenarios: [],
                bugItems: [],
                severitySummary: "No blocking issues",
                releaseRecommendation: .ready,
                summary: ["Debug complete"],
                coverageScore: 92
            )
        )

        let result = services.workflowService.submitReviewDecision(for: ticket, approved: true, comment: "Ship it")

        XCTAssertTrue(try XCTUnwrap(result).passed)
        XCTAssertEqual(ticket.stageEnum, .complete)
        XCTAssertEqual(ticket.statusEnum, .complete)
        XCTAssertEqual(ticket.handoverStateEnum, .complete)
    }

    func testDevExecutionWithFailedBuildBlocksHandover() throws {
        let services = try TestSupport.makeServices()
        let project = TestSupport.seedProject(projectService: services.projectService)
        let ticket = TestSupport.seedTicket(projectService: services.projectService, project: project, stage: .dev)

        services.workflowService.upsertDevExecution(
            for: ticket,
            input: DevExecutionInput(
                branch: "codex/provider-runtime",
                commitList: [],
                changedFiles: [FileChange(path: "Runtime.swift", status: "modified", additions: 24, deletions: 3)],
                previewURLs: [],
                implementationNotes: ["Implemented provider selection"],
                buildStatus: .failed,
                summary: ["Build is failing"],
                commitMessage: nil
            )
        )

        let gate = services.workflowService.requestHandover(for: ticket)

        XCTAssertFalse(gate.passed)
        XCTAssertTrue(gate.missingFields.contains("buildStatus"))
    }

    func testTicketContextIncludesGlobalMobileTargets() throws {
        let services = try TestSupport.makeServices()
        let project = TestSupport.seedProject(projectService: services.projectService)
        project.projectType = ProjectType.mobileApp.rawValue
        project.mobilePlatforms = [MobilePlatform.ios.rawValue, MobilePlatform.android.rawValue]
        project.screenSizes = ["mobile"]
        project.responsiveBehavior = ResponsiveBehavior.fluid.rawValue
        project.techStack = "SwiftUI, Kotlin Multiplatform"
        services.projectService.updateProject(project)

        let ticket = TestSupport.seedTicket(projectService: services.projectService, project: project, stage: .planning)
        let context = services.workflowService.ticketContext(for: ticket, project: project)

        let projectContext = try XCTUnwrap(context["project"] as? [String: Any])
        XCTAssertEqual(projectContext["type"] as? String, ProjectType.mobileApp.rawValue)
        XCTAssertEqual(projectContext["mobile_platforms"] as? [String], [MobilePlatform.ios.rawValue, MobilePlatform.android.rawValue])
        XCTAssertEqual(projectContext["screen_sizes"] as? [String], ["mobile"])
        XCTAssertEqual(projectContext["responsive_behavior"] as? String, ResponsiveBehavior.fluid.rawValue)
    }
}

@MainActor
private final class MockExternalAgentRunnerService: ExternalAgentRunnerService {
    struct RunCall {
        let client: ExternalAgentClient
        let projectDirectory: String
        let prompt: String
    }

    var runCalls: [RunCall] = []
    var result = ExternalAgentRunResult(
        client: .codex,
        terminationStatus: 0,
        finalMessage: "Planning summary",
        errorOutput: ""
    )

    override func resolvePreferredClient(
        connectionStatus: MCPConnectionStatusSnapshot,
        claudeStatus: ClaudeMCPRegistrationStatus
    ) -> ExternalAgentClient? {
        .codex
    }

    override func run(
        client: ExternalAgentClient,
        projectDirectory: String,
        prompt: String,
        onThought: @escaping @MainActor (String) -> Void,
        onAssistantDelta: @escaping @MainActor (String) -> Void
    ) async throws -> ExternalAgentRunResult {
        runCalls.append(RunCall(client: client, projectDirectory: projectDirectory, prompt: prompt))
        onThought("Starting external test runner")
        onAssistantDelta(result.finalMessage)
        return ExternalAgentRunResult(
            client: client,
            terminationStatus: result.terminationStatus,
            finalMessage: result.finalMessage,
            errorOutput: result.errorOutput
        )
    }
}
