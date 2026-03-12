import XCTest
@testable import DevJourney

@MainActor
final class MCPServerTests: XCTestCase {

    func testExtractMessageSupportsContentLengthAndClaudeNewlineFraming() throws {
        let payload = #"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-11-25"}}"#
        let contentLengthFrame = "Content-Length: \(payload.utf8.count)\r\n\r\n\(payload)"
        let newlineFrame = payload + "\n"

        let extractedContentLength = try XCTUnwrap(
            MCPServer.extractMessage(from: Data(contentLengthFrame.utf8))
        )
        XCTAssertEqual(extractedContentLength.encoding, .contentLength)
        XCTAssertEqual(String(data: extractedContentLength.message, encoding: .utf8), payload)

        let extractedNewline = try XCTUnwrap(
            MCPServer.extractMessage(from: Data(newlineFrame.utf8))
        )
        XCTAssertEqual(extractedNewline.encoding, .newlineDelimited)
        XCTAssertEqual(String(data: extractedNewline.message, encoding: .utf8), payload)
    }

    func testInitializeAndDiscoveryPayloadsExposeWorkflowToolsAndPrompts() throws {
        let services = try TestSupport.makeServices()
        let server = TestSupport.makeMCPServer(services: services)

        let initialize = server.initializePayload(clientInfo: ["name": "XCTest"])
        XCTAssertEqual(initialize["protocolVersion"] as? String, "2024-11-05")
        XCTAssertEqual(server.connectedClient, "XCTest")

        let claudeInitialize = server.initializePayload(
            clientInfo: ["name": "claude-code"],
            protocolVersion: "2025-11-25"
        )
        XCTAssertEqual(claudeInitialize["protocolVersion"] as? String, "2025-11-25")

        let tools = try XCTUnwrap(server.toolDefinitionsPayload()["tools"] as? [[String: Any]])
        let toolNames = Set(tools.compactMap { $0["name"] as? String })
        XCTAssertTrue(toolNames.contains("get_ticket_context"))
        XCTAssertTrue(toolNames.contains("upsert_planning_spec"))
        XCTAssertTrue(toolNames.contains("request_handover"))
        XCTAssertTrue(toolNames.contains("submit_review_decision"))

        let prompts = try XCTUnwrap(server.promptDefinitionsPayload()["prompts"] as? [[String: Any]])
        let promptNames = Set(prompts.compactMap { $0["name"] as? String })
        XCTAssertEqual(promptNames, ["planning_agent", "design_agent", "dev_agent", "debug_agent"])

        let resourceTemplates = try XCTUnwrap(
            server.resourceTemplateDefinitionsPayload()["resourceTemplates"] as? [[String: Any]]
        )
        XCTAssertTrue(resourceTemplates.isEmpty)

        let prompt = try XCTUnwrap(server.promptPayload(name: "planning_agent", arguments: ["ticket_id": "ticket-123"]))
        let messages = try XCTUnwrap(prompt["messages"] as? [[String: Any]])
        XCTAssertFalse(messages.isEmpty)
    }

    func testArtifactToolsUpdateContextAndGateResult() async throws {
        let services = try TestSupport.makeServices()
        let server = TestSupport.makeMCPServer(services: services)

        let project = TestSupport.seedProject(projectService: services.projectService)
        let ticket = TestSupport.seedTicket(projectService: services.projectService, project: project, stage: .planning)

        let upsertResponse = await server.callToolLocally(
            name: "upsert_planning_spec",
            arguments: [
                "ticket_id": ticket.id,
                "problem": "Implement the workflow runtime",
                "scope_in": ["Stage runtime", "Provider settings"],
                "acceptance_criteria": ["Artifacts persist"],
                "definition_of_ready": ["Provider configured"],
                "risks": ["Migration"],
                "subtasks": ["Seed providers"],
                "summary": ["Planning artifact saved"],
                "planning_score": 88
            ]
        )
        XCTAssertEqual(try TestSupport.textContent(from: upsertResponse), "Planning spec updated for ticket \(ticket.id).")

        let contextResponse = await server.callToolLocally(
            name: "get_ticket_context",
            arguments: ["ticket_id": ticket.id]
        )
        let context = try TestSupport.jsonObject(from: TestSupport.textContent(from: contextResponse))
        let artifacts = try XCTUnwrap(context["artifacts"] as? [String: Any])
        XCTAssertEqual(artifacts["planning"] as? [String], ["Planning artifact saved"])

        let handoverResponse = await server.callToolLocally(
            name: "request_handover",
            arguments: ["ticket_id": ticket.id]
        )
        let gate = try TestSupport.jsonObject(from: TestSupport.textContent(from: handoverResponse))
        XCTAssertEqual(gate["passed"] as? Bool, true)
        XCTAssertEqual(gate["score"] as? Double, 88)
    }

    func testInvalidHandoverAndClarificationAnswerFlow() async throws {
        let services = try TestSupport.makeServices()
        let server = TestSupport.makeMCPServer(services: services)

        let project = TestSupport.seedProject(projectService: services.projectService)
        let ticket = TestSupport.seedTicket(projectService: services.projectService, project: project, stage: .planning)

        let failedHandoverResponse = await server.callToolLocally(
            name: "request_handover",
            arguments: ["ticket_id": ticket.id]
        )
        let failedGate = try TestSupport.jsonObject(from: TestSupport.textContent(from: failedHandoverResponse))
        XCTAssertEqual(failedGate["passed"] as? Bool, false)
        XCTAssertTrue((failedGate["missing_fields"] as? [String] ?? []).contains("problem"))

        _ = await server.callToolLocally(
            name: "request_clarification",
            arguments: [
                "ticket_id": ticket.id,
                "question": "Which provider should be used?"
            ]
        )
        XCTAssertEqual(ticket.statusEnum, .clarify)
        XCTAssertEqual(ticket.handoverStateEnum, .blocked)
        XCTAssertEqual(ticket.pendingClarificationCount, 1)

        let answerResponse = await server.callToolLocally(
            name: "answer_clarification",
            arguments: [
                "ticket_id": ticket.id,
                "answer": "Use OpenAI."
            ]
        )
        XCTAssertEqual(try TestSupport.textContent(from: answerResponse), "Clarification answered for ticket \(ticket.id).")
        XCTAssertEqual(ticket.pendingClarificationCount, 0)
        XCTAssertEqual(ticket.statusEnum, .ready)
        XCTAssertEqual(ticket.handoverStateEnum, .idle)
    }

    func testProjectFileToolsCanWriteReadAndDeleteFiles() async throws {
        let services = try TestSupport.makeServices()
        let server = TestSupport.makeMCPServer(services: services)

        let project = TestSupport.seedProject(projectService: services.projectService)
        _ = project

        let writeResponse = await server.callToolLocally(
            name: "write_project_file",
            arguments: [
                "path": "Sources/Generated/Example.swift",
                "content": "struct Example { let value = 1 }\n"
            ]
        )
        XCTAssertTrue(try TestSupport.textContent(from: writeResponse).contains("Wrote"))

        let readResponse = await server.callToolLocally(
            name: "read_project_file",
            arguments: [
                "path": "Sources/Generated/Example.swift"
            ]
        )
        XCTAssertEqual(
            try TestSupport.textContent(from: readResponse),
            "struct Example { let value = 1 }\n"
        )

        let deleteResponse = await server.callToolLocally(
            name: "delete_project_file",
            arguments: [
                "path": "Sources/Generated/Example.swift"
            ]
        )
        XCTAssertEqual(
            try TestSupport.textContent(from: deleteResponse),
            "Deleted Sources/Generated/Example.swift."
        )
    }

    func testInputCloseStopsServerAndRequestsTermination() throws {
        let services = try TestSupport.makeServices()
        var terminationCount = 0
        let server = TestSupport.retain(MCPServer(
            connectionStatusStore: services.mcpConnectionStatusStore,
            terminationHandler: {
            terminationCount += 1
        }))
        server.configure(
            modelContainer: services.container,
            projectService: services.projectService,
            gitHubService: services.gitHubService,
            workflowService: services.workflowService
        )

        server.start()
        XCTAssertTrue(server.isRunning)

        server.handleInputClosed()

        XCTAssertFalse(server.isRunning)
        XCTAssertEqual(terminationCount, 1)
    }
}
