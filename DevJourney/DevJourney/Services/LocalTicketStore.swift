import Foundation

struct StoredTicketSnapshot {
    let ticket: TicketRecord
    let planning: PlanningRecord?
    let design: DesignRecord?
    let devExecution: DevExecutionRecord?
    let debugReport: DebugReportRecord?
    let clarifications: [ClarificationRecord]
    let reviews: [ReviewRecord]
    let sessions: [SessionRecord]
}

final class LocalTicketStore {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func syncProject(_ project: Project, tickets: [Ticket]) throws {
        try ensureProjectStructure(for: project)
        try writeJSON(projectRecord(for: project), to: projectManifestURL(for: project))

        let validTicketIDs = Set(tickets.map(\.id))
        try removeOrphanedTicketFolders(for: project, validTicketIDs: validTicketIDs)

        for ticket in tickets {
            try syncTicket(ticket, project: project)
        }
    }

    func syncTicket(_ ticket: Ticket, project: Project) throws {
        try ensureProjectStructure(for: project)

        let destinationDirectory = try ticketDirectory(for: ticket, project: project, createIfNeeded: true)
        let staleDirectory = otherBucketDirectory(for: ticket, project: project)
            .appendingPathComponent(ticket.id, isDirectory: true)
        if staleDirectory != destinationDirectory, fileManager.fileExists(atPath: staleDirectory.path) {
            try fileManager.removeItem(at: staleDirectory)
        }

        try writeJSON(ticketRecord(for: ticket), to: destinationDirectory.appendingPathComponent("ticket.json"))
        try writeOptionalJSON(planningRecord(for: ticket.latestPlanningSpec), to: destinationDirectory.appendingPathComponent("planning.json"))
        try writeOptionalJSON(designRecord(for: ticket.latestDesignSpec), to: destinationDirectory.appendingPathComponent("design.json"))
        try writeOptionalJSON(devExecutionRecord(for: ticket.latestDevExecution), to: destinationDirectory.appendingPathComponent("dev-execution.json"))
        try writeOptionalJSON(debugReportRecord(for: ticket.latestDebugReport), to: destinationDirectory.appendingPathComponent("debug-report.json"))
        try writeJSON(clarificationRecords(for: ticket), to: destinationDirectory.appendingPathComponent("clarifications.json"))
        try writeJSON(reviewRecords(for: ticket), to: destinationDirectory.appendingPathComponent("reviews.json"))
        try writeJSON(sessionRecords(for: ticket), to: destinationDirectory.appendingPathComponent("sessions.json"))
    }

    func removeTicket(_ ticket: Ticket, project: Project) throws {
        let workingDirectory = workingTicketsDirectory(for: project)
            .appendingPathComponent(ticket.id, isDirectory: true)
        let doneDirectory = doneTicketsDirectory(for: project)
            .appendingPathComponent(ticket.id, isDirectory: true)

        if fileManager.fileExists(atPath: workingDirectory.path) {
            try fileManager.removeItem(at: workingDirectory)
        }

        if fileManager.fileExists(atPath: doneDirectory.path) {
            try fileManager.removeItem(at: doneDirectory)
        }
    }

    func loadTicketSnapshots(for project: Project) throws -> [StoredTicketSnapshot] {
        let root = storeRootDirectory(for: project)
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        let directories = try storedTicketDirectories(for: project)
        return try directories.map(loadSnapshot(from:))
            .sorted { $0.ticket.createdAt > $1.ticket.createdAt }
    }

    func loadProjectRecord(at folderPath: String) throws -> ProjectRecord? {
        let manifestURL = URL(fileURLWithPath: folderPath, isDirectory: true)
            .appendingPathComponent("DevJourney", isDirectory: true)
            .appendingPathComponent("project.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        return try readJSON(ProjectRecord.self, from: manifestURL)
    }

    private func ensureProjectStructure(for project: Project) throws {
        try fileManager.createDirectory(at: storeRootDirectory(for: project), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workingTicketsDirectory(for: project), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: doneTicketsDirectory(for: project), withIntermediateDirectories: true)
    }

    private func removeOrphanedTicketFolders(for project: Project, validTicketIDs: Set<String>) throws {
        for bucket in [workingTicketsDirectory(for: project), doneTicketsDirectory(for: project)] {
            let contents = try fileManager.contentsOfDirectory(
                at: bucket,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            for entry in contents where validTicketIDs.contains(entry.lastPathComponent) == false {
                try fileManager.removeItem(at: entry)
            }
        }
    }

    private func storedTicketDirectories(for project: Project) throws -> [URL] {
        try [workingTicketsDirectory(for: project), doneTicketsDirectory(for: project)]
            .flatMap { bucket in
                try fileManager.contentsOfDirectory(
                    at: bucket,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )
            }
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            }
    }

    private func loadSnapshot(from directory: URL) throws -> StoredTicketSnapshot {
        StoredTicketSnapshot(
            ticket: try readJSON(TicketRecord.self, from: directory.appendingPathComponent("ticket.json")),
            planning: try readOptionalJSON(PlanningRecord.self, from: directory.appendingPathComponent("planning.json")),
            design: try readOptionalJSON(DesignRecord.self, from: directory.appendingPathComponent("design.json")),
            devExecution: try readOptionalJSON(DevExecutionRecord.self, from: directory.appendingPathComponent("dev-execution.json")),
            debugReport: try readOptionalJSON(DebugReportRecord.self, from: directory.appendingPathComponent("debug-report.json")),
            clarifications: try readOptionalJSON([ClarificationRecord].self, from: directory.appendingPathComponent("clarifications.json")) ?? [],
            reviews: try readOptionalJSON([ReviewRecord].self, from: directory.appendingPathComponent("reviews.json")) ?? [],
            sessions: try readOptionalJSON([SessionRecord].self, from: directory.appendingPathComponent("sessions.json")) ?? []
        )
    }

    private func writeOptionalJSON<T: Encodable>(_ value: T?, to url: URL) throws {
        if let value {
            try writeJSON(value, to: url)
        } else if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func readOptionalJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try readJSON(type, from: url)
    }

    private func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private func ticketDirectory(for ticket: Ticket, project: Project, createIfNeeded: Bool) throws -> URL {
        let directory = bucketDirectory(for: ticket, project: project)
            .appendingPathComponent(ticket.id, isDirectory: true)
        if createIfNeeded {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private func bucketDirectory(for ticket: Ticket, project: Project) -> URL {
        isDone(ticket) ? doneTicketsDirectory(for: project) : workingTicketsDirectory(for: project)
    }

    private func otherBucketDirectory(for ticket: Ticket, project: Project) -> URL {
        isDone(ticket) ? workingTicketsDirectory(for: project) : doneTicketsDirectory(for: project)
    }

    private func isDone(_ ticket: Ticket) -> Bool {
        ticket.stageEnum == .complete || ticket.statusEnum == .complete || ticket.handoverStateEnum == .complete
    }

    private func projectManifestURL(for project: Project) -> URL {
        storeRootDirectory(for: project).appendingPathComponent("project.json")
    }

    private func storeRootDirectory(for project: Project) -> URL {
        URL(fileURLWithPath: project.folderPath, isDirectory: true)
            .appendingPathComponent("DevJourney", isDirectory: true)
    }

    private func workingTicketsDirectory(for project: Project) -> URL {
        storeRootDirectory(for: project)
            .appendingPathComponent("tickets", isDirectory: true)
            .appendingPathComponent("working", isDirectory: true)
    }

    private func doneTicketsDirectory(for project: Project) -> URL {
        storeRootDirectory(for: project)
            .appendingPathComponent("tickets", isDirectory: true)
            .appendingPathComponent("done", isDirectory: true)
    }

    private func projectRecord(for project: Project) -> ProjectRecord {
        ProjectRecord(
            id: project.id,
            name: project.name,
            description: project.projectDescription,
            projectType: project.projectType,
            folderPath: project.folderPath,
            githubRepo: project.githubRepo,
            screenSizes: project.screenSizes,
            responsiveBehavior: project.responsiveBehavior,
            techStack: project.techStack,
            mobilePlatforms: project.normalizedMobilePlatforms,
            createdAt: project.createdAt
        )
    }

    private func ticketRecord(for ticket: Ticket) -> TicketRecord {
        TicketRecord(
            id: ticket.id,
            title: ticket.title,
            description: ticket.ticketDescription,
            priority: ticket.priority,
            tags: ticket.tags,
            stage: ticket.stage,
            status: ticket.status,
            handoverState: ticket.handoverState,
            blockedReason: ticket.blockedReason,
            activeProviderConfigId: ticket.activeProviderConfigId,
            activeModel: ticket.activeModel,
            agentCount: ticket.agentCount,
            createdAt: ticket.createdAt,
            updatedAt: ticket.updatedAt,
            pendingClarificationCount: ticket.pendingClarificationCount
        )
    }

    private func clarificationRecords(for ticket: Ticket) -> [ClarificationRecord] {
        ticket.clarifications
            .sorted { $0.id < $1.id }
            .map {
                ClarificationRecord(
                    id: $0.id,
                    stage: $0.stage,
                    question: $0.question,
                    answer: $0.answer,
                    answeredAt: $0.answeredAt
                )
            }
    }

    private func reviewRecords(for ticket: Ticket) -> [ReviewRecord] {
        ticket.reviewResults
            .sorted { $0.createdAt < $1.createdAt }
            .map {
                ReviewRecord(
                    id: $0.id,
                    stage: $0.stage,
                    approved: $0.approved,
                    reviewerComment: $0.reviewerComment,
                    approvedAt: $0.approvedAt,
                    createdAt: $0.createdAt
                )
            }
    }

    private func sessionRecords(for ticket: Ticket) -> [SessionRecord] {
        ticket.sessions
            .sorted { $0.startedAt < $1.startedAt }
            .map {
                SessionRecord(
                    id: $0.id,
                    stage: $0.stage,
                    providerId: $0.providerId,
                    modelUsed: $0.modelUsed,
                    startedAt: $0.startedAt,
                    endedAt: $0.endedAt,
                    liveResponse: $0.liveResponse,
                    errorMessage: $0.errorMessage,
                    thoughts: $0.thoughts,
                    dialog: $0.dialog,
                    executionEvents: $0.executionEvents,
                    resultSummary: $0.resultSummary,
                    filesChanged: $0.filesChanged,
                    commitCount: $0.commitCount
                )
            }
    }

    private func planningRecord(for spec: PlanningSpec?) -> PlanningRecord? {
        guard let spec else { return nil }
        return PlanningRecord(
            id: spec.id,
            problem: spec.problem,
            scopeIn: spec.scopeIn,
            scopeOut: spec.scopeOut,
            acceptanceCriteria: spec.acceptanceCriteria,
            dependencies: spec.dependencies,
            assumptions: spec.assumptions,
            risks: spec.risks,
            subtasks: spec.subtasks,
            definitionOfReady: spec.definitionOfReady,
            summary: spec.summary,
            planningScore: spec.planningScore,
            updatedAt: spec.updatedAt
        )
    }

    private func designRecord(for spec: DesignSpec?) -> DesignRecord? {
        guard let spec else { return nil }
        return DesignRecord(
            id: spec.id,
            appPlacement: spec.appPlacement,
            affectedScreens: spec.affectedScreens,
            userFlow: spec.userFlow,
            components: spec.components,
            microcopy: spec.microcopy,
            statesMatrix: spec.statesMatrix,
            responsiveRules: spec.responsiveRules,
            accessibilityNotes: spec.accessibilityNotes,
            figmaRefs: spec.figmaRefs,
            summary: spec.summary,
            designScore: spec.designScore,
            updatedAt: spec.updatedAt
        )
    }

    private func devExecutionRecord(for execution: DevExecution?) -> DevExecutionRecord? {
        guard let execution else { return nil }
        return DevExecutionRecord(
            id: execution.id,
            branch: execution.branch,
            commitList: execution.commitList,
            changedFiles: execution.changedFiles,
            previewURLs: execution.previewURLs,
            implementationNotes: execution.implementationNotes,
            buildStatus: execution.buildStatus,
            summary: execution.summary,
            updatedAt: execution.updatedAt
        )
    }

    private func debugReportRecord(for report: DebugReport?) -> DebugReportRecord? {
        guard let report else { return nil }
        return DebugReportRecord(
            id: report.id,
            testedScenarios: report.testedScenarios,
            failedScenarios: report.failedScenarios,
            bugItems: report.bugItems,
            severitySummary: report.severitySummary,
            releaseRecommendation: report.releaseRecommendation,
            summary: report.summary,
            coverageScore: report.coverageScore,
            updatedAt: report.updatedAt
        )
    }
}

struct ProjectRecord: Codable {
    let id: String
    let name: String
    let description: String
    let projectType: String
    let folderPath: String
    let githubRepo: String?
    let screenSizes: [String]
    let responsiveBehavior: String
    let techStack: String
    let mobilePlatforms: [String]?
    let createdAt: Date
}

struct TicketRecord: Codable {
    let id: String
    let title: String
    let description: String
    let priority: String
    let tags: [String]
    let stage: String
    let status: String
    let handoverState: String
    let blockedReason: String?
    let activeProviderConfigId: String?
    let activeModel: String?
    let agentCount: Int
    let createdAt: Date
    let updatedAt: Date
    let pendingClarificationCount: Int
}

struct ClarificationRecord: Codable {
    let id: String
    let stage: String
    let question: String
    let answer: String?
    let answeredAt: Date?
}

struct ReviewRecord: Codable {
    let id: String
    let stage: String
    let approved: Bool
    let reviewerComment: String?
    let approvedAt: Date?
    let createdAt: Date
}

struct SessionRecord: Codable {
    let id: String
    let stage: String
    let providerId: String?
    let modelUsed: String
    let startedAt: Date
    let endedAt: Date?
    let liveResponse: String
    let errorMessage: String?
    let thoughts: [String]
    let dialog: [DialogEntry]
    let executionEvents: [AgentExecutionEvent]
    let resultSummary: [String]
    let filesChanged: [FileChange]
    let commitCount: Int
}

struct PlanningRecord: Codable {
    let id: String
    let problem: String
    let scopeIn: [String]
    let scopeOut: [String]
    let acceptanceCriteria: [String]
    let dependencies: [String]
    let assumptions: [String]
    let risks: [String]
    let subtasks: [String]
    let definitionOfReady: [String]
    let summary: [String]
    let planningScore: Double
    let updatedAt: Date
}

struct DesignRecord: Codable {
    let id: String
    let appPlacement: String
    let affectedScreens: [String]
    let userFlow: [String]
    let components: [String]
    let microcopy: [String]
    let statesMatrix: [String]
    let responsiveRules: [String]
    let accessibilityNotes: [String]
    let figmaRefs: [String]
    let summary: [String]
    let designScore: Double
    let updatedAt: Date
}

struct DevExecutionRecord: Codable {
    let id: String
    let branch: String
    let commitList: [String]
    let changedFiles: [FileChange]
    let previewURLs: [String]
    let implementationNotes: [String]
    let buildStatus: String
    let summary: [String]
    let updatedAt: Date
}

struct DebugReportRecord: Codable {
    let id: String
    let testedScenarios: [String]
    let failedScenarios: [String]
    let bugItems: [String]
    let severitySummary: String
    let releaseRecommendation: String
    let summary: [String]
    let coverageScore: Double
    let updatedAt: Date
}
