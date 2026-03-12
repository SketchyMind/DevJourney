import Foundation
import SwiftData

@MainActor
class ProjectService {
    private let modelContainer: ModelContainer
    private let localTicketStore: LocalTicketStore

    init(modelContainer: ModelContainer, localTicketStore: LocalTicketStore) {
        self.modelContainer = modelContainer
        self.localTicketStore = localTicketStore
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

    func findProject(folderPath: String) -> Project? {
        let normalizedFolderPath = URL(fileURLWithPath: folderPath, isDirectory: true)
            .standardizedFileURL.path
        return loadProjects().first {
            URL(fileURLWithPath: $0.folderPath, isDirectory: true).standardizedFileURL.path == normalizedFolderPath
        }
    }

    func loadOrImportProject(folderPath: String) -> Project? {
        if let existing = findProject(folderPath: folderPath) {
            return existing
        }

        guard let record = try? localTicketStore.loadProjectRecord(at: folderPath) else {
            return nil
        }

        let project = Project(
            id: record.id,
            name: record.name,
            projectDescription: record.description,
            projectType: record.projectType,
            folderPath: record.folderPath,
            githubRepo: record.githubRepo,
            screenSizes: record.screenSizes,
            responsiveBehavior: record.responsiveBehavior,
            techStack: record.techStack,
            mobilePlatforms: record.mobilePlatforms ?? []
        )
        project.createdAt = record.createdAt
        context.insert(project)
        save()
        restoreTicketsFromLocalStore(for: project)
        ensureDefaultProviderConfigs(for: project)
        return project
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
        syncProject(project)
        return project
    }

    func restoreTicketsFromLocalStore(for project: Project) {
        guard let snapshots = try? localTicketStore.loadTicketSnapshots(for: project),
              !snapshots.isEmpty else {
            return
        }

        let existingTickets = getProjectTickets(projectId: project.id)
        for ticket in existingTickets {
            context.delete(ticket)
        }
        save()

        for snapshot in snapshots {
            let record = snapshot.ticket
            let ticket = Ticket(
                id: record.id,
                title: record.title,
                ticketDescription: record.description,
                priority: Priority(rawValue: record.priority) ?? .medium,
                projectId: project.id
            )
            ticket.tags = record.tags
            ticket.stage = record.stage
            ticket.status = record.status
            ticket.handoverState = record.handoverState
            ticket.blockedReason = record.blockedReason
            ticket.activeProviderConfigId = record.activeProviderConfigId
            ticket.activeModel = record.activeModel
            ticket.agentCount = max(1, record.agentCount)
            ticket.createdAt = record.createdAt
            ticket.updatedAt = record.updatedAt
            context.insert(ticket)
            project.tickets.append(ticket)

            if let planning = snapshot.planning {
                let spec = PlanningSpec(
                    id: planning.id,
                    ticketId: ticket.id,
                    problem: planning.problem,
                    scopeIn: planning.scopeIn,
                    scopeOut: planning.scopeOut,
                    acceptanceCriteria: planning.acceptanceCriteria,
                    dependencies: planning.dependencies,
                    assumptions: planning.assumptions,
                    risks: planning.risks,
                    subtasks: planning.subtasks,
                    definitionOfReady: planning.definitionOfReady,
                    summary: planning.summary,
                    planningScore: planning.planningScore
                )
                spec.updatedAt = planning.updatedAt
                context.insert(spec)
                ticket.planningSpecs.append(spec)
            }

            if let design = snapshot.design {
                let spec = DesignSpec(
                    id: design.id,
                    ticketId: ticket.id,
                    appPlacement: design.appPlacement,
                    affectedScreens: design.affectedScreens,
                    userFlow: design.userFlow,
                    components: design.components,
                    microcopy: design.microcopy,
                    statesMatrix: design.statesMatrix,
                    responsiveRules: design.responsiveRules,
                    accessibilityNotes: design.accessibilityNotes,
                    figmaRefs: design.figmaRefs,
                    summary: design.summary,
                    designScore: design.designScore
                )
                spec.updatedAt = design.updatedAt
                context.insert(spec)
                ticket.designSpecs.append(spec)
            }

            if let devExecution = snapshot.devExecution {
                let execution = DevExecution(
                    id: devExecution.id,
                    ticketId: ticket.id,
                    branch: devExecution.branch,
                    commitList: devExecution.commitList,
                    changedFiles: devExecution.changedFiles,
                    previewURLs: devExecution.previewURLs,
                    implementationNotes: devExecution.implementationNotes,
                    buildStatus: BuildStatus(rawValue: devExecution.buildStatus) ?? .notRun,
                    summary: devExecution.summary
                )
                execution.updatedAt = devExecution.updatedAt
                context.insert(execution)
                ticket.devExecutions.append(execution)
            }

            if let debugReport = snapshot.debugReport {
                let report = DebugReport(
                    id: debugReport.id,
                    ticketId: ticket.id,
                    testedScenarios: debugReport.testedScenarios,
                    failedScenarios: debugReport.failedScenarios,
                    bugItems: debugReport.bugItems,
                    severitySummary: debugReport.severitySummary,
                    releaseRecommendation: ReleaseRecommendation(rawValue: debugReport.releaseRecommendation) ?? .pending,
                    summary: debugReport.summary,
                    coverageScore: debugReport.coverageScore
                )
                report.updatedAt = debugReport.updatedAt
                context.insert(report)
                ticket.debugReports.append(report)
            }

            for clarification in snapshot.clarifications {
                let item = ClarificationItem(
                    id: clarification.id,
                    ticketId: ticket.id,
                    stage: clarification.stage,
                    question: clarification.question
                )
                item.answer = clarification.answer
                item.answeredAt = clarification.answeredAt
                context.insert(item)
                ticket.clarifications.append(item)
            }

            for review in snapshot.reviews {
                let result = ReviewResult(
                    id: review.id,
                    ticketId: ticket.id,
                    stage: review.stage,
                    approved: review.approved
                )
                result.reviewerComment = review.reviewerComment
                result.approvedAt = review.approvedAt
                result.createdAt = review.createdAt
                context.insert(result)
                ticket.reviewResults.append(result)
            }

            for sessionRecord in snapshot.sessions {
                let session = AgentSession(
                    id: sessionRecord.id,
                    ticketId: ticket.id,
                    stage: sessionRecord.stage,
                    providerId: sessionRecord.providerId,
                    modelUsed: sessionRecord.modelUsed
                )
                session.startedAt = sessionRecord.startedAt
                session.endedAt = sessionRecord.endedAt
                session.liveResponse = sessionRecord.liveResponse
                session.errorMessage = sessionRecord.errorMessage
                session.thoughts = sessionRecord.thoughts
                session.dialog = sessionRecord.dialog
                session.executionEvents = sessionRecord.executionEvents
                session.resultSummary = sessionRecord.resultSummary
                session.filesChanged = sessionRecord.filesChanged
                session.commitCount = sessionRecord.commitCount
                context.insert(session)
                ticket.sessions.append(session)
            }
        }

        save()
    }

    func updateProject(_ project: Project) {
        save()
        syncProject(project)
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
        tags: [String] = [],
        agentCount: Int = 1
    ) -> Ticket {
        let ticket = Ticket(
            title: title,
            ticketDescription: ticketDescription,
            priority: priority,
            projectId: projectId
        )
        ticket.tags = tags
        ticket.agentCount = agentCount
        context.insert(ticket)
        save()
        syncTicketIfPossible(ticket)
        return ticket
    }

    func updateTicket(_ ticket: Ticket) {
        ticket.updatedAt = Date()
        save()
        syncTicketIfPossible(ticket)
    }

    func deleteTicket(_ ticket: Ticket) {
        if let project = project(for: ticket.projectId) {
            try? localTicketStore.removeTicket(ticket, project: project)
        }
        context.delete(ticket)
        save()
    }

    func moveTicket(_ ticket: Ticket, to stage: Stage) {
        ticket.setStage(stage)
        save()
        syncTicketIfPossible(ticket)
    }

    func updateProjectSettings(
        _ project: Project,
        name: String,
        description: String,
        projectType: String,
        githubRepo: String?,
        screenSizes: [String],
        responsiveBehavior: String,
        techStack: String,
        mobilePlatforms: [String]
    ) {
        project.name = name
        project.projectDescription = description
        project.projectType = projectType
        project.githubRepo = githubRepo
        project.screenSizes = screenSizes
        project.responsiveBehavior = responsiveBehavior
        project.techStack = techStack
        project.mobilePlatforms = projectType == ProjectType.mobileApp.rawValue ? mobilePlatforms : []
        save()
        syncProject(project)
    }

    func ensureDefaultProviderConfigs(for project: Project) {
        let existingKinds = Set(project.providerConfigs.map(\.kindEnum))

        if !existingKinds.contains(.anthropic) {
            let config = AIProviderConfig(projectId: project.id, kind: .anthropic)
            context.insert(config)
            project.providerConfigs.append(config)
        }

        if !existingKinds.contains(.openAI) {
            let config = AIProviderConfig(projectId: project.id, kind: .openAI)
            context.insert(config)
            project.providerConfigs.append(config)
        }

        if !existingKinds.contains(.openAICompatible) {
            let config = AIProviderConfig(
                projectId: project.id,
                kind: .openAICompatible,
                enabled: false
            )
            context.insert(config)
            project.providerConfigs.append(config)
        }

        if project.planningProviderConfigId == nil {
            let fallback = project.providerConfigs.first(where: { $0.kindEnum == .anthropic })?.id
                ?? project.providerConfigs.first?.id
            project.planningProviderConfigId = fallback
            project.designProviderConfigId = fallback
            project.devProviderConfigId = fallback
            project.debugProviderConfigId = fallback
        }

        save()
        syncProject(project)
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }

    private func project(for id: String) -> Project? {
        let localID = id
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate<Project> { $0.id == localID })
        return try? context.fetch(descriptor).first
    }

    private func syncProject(_ project: Project) {
        let tickets = getProjectTickets(projectId: project.id)
        try? localTicketStore.syncProject(project, tickets: tickets)
    }

    private func syncTicketIfPossible(_ ticket: Ticket) {
        guard let project = project(for: ticket.projectId) else { return }
        try? localTicketStore.syncTicket(ticket, project: project)
    }
}
