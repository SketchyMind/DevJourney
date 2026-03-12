import Foundation
import SwiftData

/// Context passed to every MCP tool handler, providing access to app services.
struct MCPToolContext: Sendable {
    let modelContainer: ModelContainer
    let projectService: ProjectService
    let gitHubService: GitHubService
    let workflowService: TicketWorkflowService
}
