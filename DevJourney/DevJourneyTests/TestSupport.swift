import Foundation
import SwiftData
import XCTest
@testable import DevJourney

@MainActor
final class TestFixture {
    let container: ModelContainer
    let localTicketStore: LocalTicketStore
    let mcpConnectionStatusStore: MCPConnectionStatusStore
    let projectService: ProjectService
    let workflowService: TicketWorkflowService
    let gitHubService: GitHubService

    init() throws {
        let schema = Schema([
            Project.self,
            Ticket.self,
            AgentSession.self,
            ClarificationItem.self,
            ReviewResult.self,
            AIProviderConfig.self,
            PlanningSpec.self,
            DesignSpec.self,
            DevExecution.self,
            DebugReport.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        localTicketStore = LocalTicketStore()
        let mcpStatusRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("devjourney-mcp-status-\(UUID().uuidString)", isDirectory: true)
        mcpConnectionStatusStore = MCPConnectionStatusStore(rootDirectoryProvider: { mcpStatusRoot })
        projectService = ProjectService(modelContainer: container, localTicketStore: localTicketStore)
        gitHubService = GitHubService()
        workflowService = TicketWorkflowService(
            modelContainer: container,
            projectService: projectService,
            gitHubService: gitHubService,
            localTicketStore: localTicketStore
        )
    }
}

@MainActor
enum TestSupport {
    private static var retainedFixtures: [TestFixture] = []
    private static var retainedObjects: [AnyObject] = []

    static func makeServices() throws -> TestFixture {
        let fixture = try TestFixture()
        retainedFixtures.append(fixture)
        return fixture
    }

    static func seedProject(
        projectService: ProjectService,
        name: String = "DevJourney Test Project"
    ) -> Project {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("devjourney-tests-\(UUID().uuidString)", isDirectory: true)
            .path
        let project = projectService.createProject(
            name: name,
            projectDescription: "In-memory test project",
            type: .desktopApp,
            folder: folder
        )
        projectService.ensureDefaultProviderConfigs(for: project)
        return project
    }

    static func seedTicket(
        projectService: ProjectService,
        project: Project,
        title: String = "Implement workflow",
        stage: Stage
    ) -> Ticket {
        let ticket = projectService.createTicket(
            title: title,
            ticketDescription: "Ticket for \(stage.displayName) coverage",
            priority: .medium,
            projectId: project.id
        )
        ticket.setStage(stage)
        ticket.setStatus(.ready)
        return ticket
    }

    static func textContent(from response: [String: Any]) throws -> String {
        let content = try XCTUnwrap(response["content"] as? [[String: Any]])
        let first = try XCTUnwrap(content.first)
        return try XCTUnwrap(first["text"] as? String)
    }

    static func jsonObject(from text: String) throws -> [String: Any] {
        let data = try XCTUnwrap(text.data(using: .utf8))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @discardableResult
    static func retain<Object: AnyObject>(_ object: Object) -> Object {
        retainedObjects.append(object)
        return object
    }

    static func makeMCPServer(services: TestFixture) -> MCPServer {
        let server = retain(MCPServer(connectionStatusStore: services.mcpConnectionStatusStore))
        server.configure(
            modelContainer: services.container,
            projectService: services.projectService,
            gitHubService: services.gitHubService,
            workflowService: services.workflowService
        )
        return server
    }
}
