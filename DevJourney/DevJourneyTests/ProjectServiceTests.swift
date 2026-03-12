import XCTest
import SwiftData
@testable import DevJourney

@MainActor
final class ProjectServiceTests: XCTestCase {

    func testRestoreTicketsFromLocalStoreRehydratesSavedTicketsAndArtifacts() throws {
        let firstServices = try TestSupport.makeServices()
        let project = TestSupport.seedProject(projectService: firstServices.projectService)
        let ticket = firstServices.projectService.createTicket(
            title: "Restore me",
            ticketDescription: "Persist ticket data locally",
            priority: .high,
            projectId: project.id
        )
        ticket.setStage(.planning)
        ticket.setStatus(.done)
        ticket.setHandoverState(.readyForReview)

        firstServices.workflowService.upsertPlanningSpec(
            for: ticket,
            input: PlanningSpecInput(
                problem: "Persist ticket state",
                scopeIn: ["Ticket JSON", "Artifact restore"],
                scopeOut: [],
                acceptanceCriteria: ["Ticket reloads on relaunch"],
                dependencies: [],
                assumptions: ["Local project folder is writable"],
                risks: [],
                subtasks: ["Write JSON", "Read JSON"],
                definitionOfReady: ["Reviewable artifact exists"],
                summary: ["Planning artifact stored on disk"],
                planningScore: 88
            )
        )

        firstServices.projectService.updateTicket(ticket)

        let secondServices = try TestSupport.makeServices()
        let restoredProject = Project(
            id: project.id,
            name: project.name,
            projectDescription: project.projectDescription,
            projectType: project.projectType,
            folderPath: project.folderPath,
            githubRepo: project.githubRepo
        )
        secondServices.container.mainContext.insert(restoredProject)
        try secondServices.container.mainContext.save()

        secondServices.projectService.restoreTicketsFromLocalStore(for: restoredProject)

        let restoredTickets = secondServices.projectService.getProjectTickets(projectId: restoredProject.id)
        XCTAssertEqual(restoredTickets.count, 1)
        XCTAssertEqual(restoredTickets.first?.title, "Restore me")
        XCTAssertEqual(restoredTickets.first?.latestPlanningSpec?.problem, "Persist ticket state")
        XCTAssertEqual(restoredTickets.first?.handoverStateEnum, .readyForReview)
    }
}
