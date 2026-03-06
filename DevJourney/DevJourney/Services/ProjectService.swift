import Foundation
import SwiftData

@MainActor
class ProjectService {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    private var context: ModelContext {
        modelContainer.mainContext
    }

    func loadProjects() -> [Project] {
        let descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Failed to load projects: \(error)")
            return []
        }
    }

    func createProject(
        name: String,
        projectDescription: String,
        type: ProjectType,
        folder: String,
        repo: String? = nil
    ) -> Project {
        let project = Project(
            name: name,
            projectDescription: projectDescription,
            projectType: type.rawValue,
            folderPath: folder,
            githubRepo: repo
        )
        context.insert(project)
        save()
        return project
    }

    func updateProject(_ project: Project) {
        save()
    }

    func deleteProject(_ project: Project) {
        context.delete(project)
        save()
    }

    func getProjectTickets(projectId: String) -> [Ticket] {
        let localProjectId = projectId
        let descriptor = FetchDescriptor<Ticket>(
            predicate: #Predicate<Ticket> { $0.projectId == localProjectId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            print("Failed to load tickets for project \(projectId): \(error)")
            return []
        }
    }

    func createTicket(
        title: String,
        ticketDescription: String,
        priority: Priority = .medium,
        projectId: String,
        aiModel: String
    ) -> Ticket {
        let ticket = Ticket(
            title: title,
            ticketDescription: ticketDescription,
            priority: priority,
            projectId: projectId,
            aiModel: aiModel
        )
        context.insert(ticket)
        save()
        return ticket
    }

    func updateTicket(_ ticket: Ticket) {
        ticket.updatedAt = Date()
        save()
    }

    func deleteTicket(_ ticket: Ticket) {
        context.delete(ticket)
        save()
    }

    func moveTicket(_ ticket: Ticket, to stage: Stage) {
        ticket.setStage(stage)
        save()
    }

    func updateProjectSettings(
        _ project: Project,
        name: String,
        description: String,
        projectType: String,
        defaultModel: String,
        defaultProvider: String,
        githubRepo: String?,
        screenSizes: [String],
        responsiveBehavior: String,
        techStack: String
    ) {
        project.name = name
        project.projectDescription = description
        project.projectType = projectType
        project.defaultModel = defaultModel
        project.defaultProvider = defaultProvider
        project.githubRepo = githubRepo
        project.screenSizes = screenSizes
        project.responsiveBehavior = responsiveBehavior
        project.techStack = techStack
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
}
