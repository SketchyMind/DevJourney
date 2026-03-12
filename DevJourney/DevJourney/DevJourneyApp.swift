import SwiftUI
import SwiftData
import Combine
import Darwin
#if canImport(AppKit)
import AppKit
#endif

@main
struct DevJourneyApp: App {
    private let isMCPMode = CommandLine.arguments.contains("--mcp")
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if isMCPMode {
                    Color.clear
                        .frame(width: 1, height: 1)
                } else if appState.currentProject != nil {
                    KanbanBoardView()
                        .environmentObject(appState)
                } else {
                    UnifiedOnboardingView()
                        .environmentObject(appState)
                }
            }
            .onAppear {
                #if canImport(AppKit)
                if isMCPMode {
                    NSApp.setActivationPolicy(.prohibited)
                    NSApp.windows.forEach { $0.orderOut(nil) }
                } else {
                    NSApp.activate()
                }
                #endif
                appState.startMCPServerIfNeeded()
            }
        }
        .modelContainer(appState.modelContainer)
    }
}

@MainActor
class AppState: ObservableObject {
    private static let lastSelectedProjectIDKey = "devjourney.lastSelectedProjectID"
    private static let recentProjectPathsKey = "devjourney.recentProjectPaths"

    @Published var currentProject: Project?
    @Published var tickets: [Ticket] = []
    @Published var activeSessions: [String: AgentSession] = [:]
    @Published var currentBranch: String = "main"
    @Published var branchIsDirty: Bool = false
    @Published var mcpConnectionStatus: MCPConnectionStatusSnapshot = .disconnected
    @Published var claudeMCPRegistrationStatus: ClaudeMCPRegistrationStatus = .init(mode: .notConfigured)

    let modelContainer: ModelContainer
    let localTicketStore: LocalTicketStore
    let projectService: ProjectService
    let gitHubService = GitHubService()
    let fileService = FileService()
    let workflowService: TicketWorkflowService
    let mcpServer = MCPServer()
    let mcpConnectionStatusStore = MCPConnectionStatusStore.shared
    let claudeMCPService = ClaudeCodeMCPService.shared
    private let isMCPMode: Bool
    private var cancellables = Set<AnyCancellable>()

    init(isMCPMode: Bool = CommandLine.arguments.contains("--mcp")) {
        self.isMCPMode = isMCPMode
        do {
            self.localTicketStore = LocalTicketStore()
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
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.projectService = ProjectService(
                modelContainer: modelContainer,
                localTicketStore: localTicketStore
            )
            self.workflowService = TicketWorkflowService(
                modelContainer: modelContainer,
                projectService: projectService,
                gitHubService: gitHubService,
                localTicketStore: localTicketStore
            )

            workflowService.$activeSessions
                .receive(on: RunLoop.main)
                .sink { [weak self] sessions in
                    self?.activeSessions = sessions
                }
                .store(in: &cancellables)

            mcpServer.configure(
                modelContainer: modelContainer,
                projectService: projectService,
                gitHubService: gitHubService,
                workflowService: workflowService
            )
            if isMCPMode {
                MCPProcessCleanup.terminateSiblingMCPProcessesForCurrentClient()
                mcpServer.start()
            }
            refreshMCPConnectionStatus()
            refreshClaudeMCPRegistrationStatus()
            Timer.publish(every: 2, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.refreshMCPConnectionStatus()
                    self?.refreshClaudeMCPRegistrationStatus()
                    self?.refreshProjectStateIfNeeded()
                }
                .store(in: &cancellables)
            if Self.shouldRefreshMCPLauncher() {
                _ = try? MCPLaunchService.shared.refreshLauncher()
            }
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    private static func shouldRefreshMCPLauncher(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["XCTestConfigurationFilePath"] == nil
    }

    func startMCPServerIfNeeded() {
        // The MCP server is bootstrapped during initialization in headless mode.
        if isMCPMode {
            mcpServer.start()
        }
        refreshMCPConnectionStatus()
        refreshClaudeMCPRegistrationStatus()
    }

    func loadProjectTickets() {
        guard let project = currentProject else {
            tickets = []
            return
        }
        tickets = projectService.getProjectTickets(projectId: project.id)
    }

    func selectProject(_ project: Project) {
        projectService.restoreTicketsFromLocalStore(for: project)
        projectService.ensureDefaultProviderConfigs(for: project)
        currentProject = project
        loadProjectTickets()
        try? localTicketStore.syncProject(project, tickets: tickets)
        UserDefaults.standard.set(project.id, forKey: Self.lastSelectedProjectIDKey)
        recordRecentProjectPath(project.folderPath)
        Task { await refreshBranchInfo() }
    }

    func showProjectPicker() {
        currentProject = nil
        tickets = []
    }

    func startStage(for ticket: Ticket) {
        guard let project = currentProject else { return }
        workflowService.startStage(
            for: ticket,
            project: project,
            mcpConnectionStatus: mcpConnectionStatus,
            claudeRegistrationStatus: claudeMCPRegistrationStatus
        )
    }

    func stopStage(for ticket: Ticket) {
        workflowService.stopStage(for: ticket)
    }

    func resumeStage(for ticket: Ticket) {
        guard let project = currentProject else { return }
        workflowService.resumeStage(
            for: ticket,
            project: project,
            mcpConnectionStatus: mcpConnectionStatus,
            claudeRegistrationStatus: claudeMCPRegistrationStatus
        )
    }

    func refreshBranchInfo() async {
        guard let project = currentProject else { return }
        let path = URL(fileURLWithPath: project.folderPath)
        let branch = await gitHubService.runGitAsync(at: path, args: ["rev-parse", "--abbrev-ref", "HEAD"]) ?? "main"
        let status = await gitHubService.runGitAsync(at: path, args: ["status", "--porcelain"])
        self.currentBranch = branch
        self.branchIsDirty = !(status?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    func syncTicketStorage(_ ticket: Ticket) {
        let resolvedProject =
            (currentProject?.id == ticket.projectId ? currentProject : nil)
            ?? projectService.loadProjects().first(where: { $0.id == ticket.projectId })

        guard let project = resolvedProject else { return }
        try? localTicketStore.syncTicket(ticket, project: project)
    }

    func answerClarification(_ item: ClarificationItem, for ticket: Ticket, response: String) {
        workflowService.answerClarification(item, for: ticket, response: response)
        guard ticket.pendingClarificationCount == 0,
              ticket.statusEnum == .ready,
              let project = currentProject,
              project.id == ticket.projectId else {
            return
        }
        workflowService.resumeStage(
            for: ticket,
            project: project,
            mcpConnectionStatus: mcpConnectionStatus,
            claudeRegistrationStatus: claudeMCPRegistrationStatus
        )
    }

    func resolveClarificationsIfPossible(for ticket: Ticket) {
        guard let project = currentProject, project.id == ticket.projectId else {
            return
        }
        _ = workflowService.reconcileClarifications(for: ticket, project: project)
    }

    func deleteTicket(_ ticket: Ticket) {
        if activeSessions[ticket.id] != nil {
            workflowService.stopStage(for: ticket)
        }
        projectService.deleteTicket(ticket)
        tickets.removeAll { $0.id == ticket.id }
        if let currentProject {
            tickets = projectService.getProjectTickets(projectId: currentProject.id)
        }
    }

    func refreshMCPConnectionStatus() {
        mcpConnectionStatus = mcpConnectionStatusStore.load()
    }

    func refreshClaudeMCPRegistrationStatus() {
        claudeMCPRegistrationStatus = claudeMCPService.loadStatus()
    }

    func refreshProjectStateIfNeeded() {
        guard let project = currentProject else { return }
        let refreshedProject = projectService.loadProjects().first(where: { $0.id == project.id }) ?? project
        currentProject = refreshedProject
        tickets = projectService.getProjectTickets(projectId: refreshedProject.id)
    }

    func recentProjects(limit: Int = 5) -> [Project] {
        let projectMap = projectService.loadProjects().reduce(into: [String: Project]()) { result, project in
            let standardizedPath = URL(fileURLWithPath: project.folderPath, isDirectory: true)
                .standardizedFileURL.path
            result[standardizedPath] = result[standardizedPath] ?? project
        }
        let existingPaths = recentProjectPaths().filter {
            FileManager.default.fileExists(atPath: $0)
        }

        return Array(existingPaths.prefix(limit)).compactMap { path in
            projectMap[path] ?? projectService.loadOrImportProject(folderPath: path)
        }
    }

    private func recentProjectPaths() -> [String] {
        UserDefaults.standard.stringArray(forKey: Self.recentProjectPathsKey) ?? []
    }

    private func recordRecentProjectPath(_ folderPath: String) {
        let standardizedPath = URL(fileURLWithPath: folderPath, isDirectory: true)
            .standardizedFileURL.path
        var updatedPaths = recentProjectPaths().filter { $0 != standardizedPath }
        updatedPaths.insert(standardizedPath, at: 0)
        UserDefaults.standard.set(Array(updatedPaths.prefix(5)), forKey: Self.recentProjectPathsKey)
    }
}

private enum MCPProcessCleanup {
    private static let currentExecutablePath = Bundle.main.executablePath ?? ""
    private static let launcherScriptPath = launcherPath()

    static func terminateSiblingMCPProcessesForCurrentClient() {
        guard !currentExecutablePath.isEmpty else { return }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let processes = processTable()
        let currentParentPID = getppid()
        guard let currentClientPID = clientPID(
            forProcessID: currentPID,
            parentPID: currentParentPID,
            in: processes
        ) else { return }

        let siblingProcessIDs = processes.compactMap { row -> Int32? in
            guard row.pid != currentPID else { return nil }
            guard row.pid != currentParentPID else { return nil }
            guard isMCPLauncherProcess(row.command) else { return nil }
            guard row.command.contains("--mcp") else { return nil }
            guard clientPID(for: row, in: processes) == currentClientPID else { return nil }
            return row.pid
        }

        for pid in siblingProcessIDs {
            kill(pid, SIGTERM)
        }
    }

    private static func clientPID(
        forProcessID pid: Int32,
        parentPID currentParentPID: Int32,
        in table: [ProcessRow]
    ) -> Int32? {
        guard let parentRow = table.first(where: { $0.pid == currentParentPID }) else {
            return currentParentPID > 1 ? currentParentPID : nil
        }

        if isLauncherShell(parentRow.command) {
            return parentPID(for: currentParentPID, in: table) ?? currentParentPID
        }

        return currentParentPID > 1 ? currentParentPID : nil
    }

    private static func clientPID(for row: ProcessRow, in table: [ProcessRow]) -> Int32? {
        if isLauncherShell(row.command) {
            return row.ppid > 1 ? row.ppid : nil
        }

        guard row.command.contains(currentExecutablePath) else { return nil }
        return parentPID(for: row.ppid, in: table) ?? row.ppid
    }

    private static func isMCPLauncherProcess(_ command: String) -> Bool {
        command.contains(currentExecutablePath) || isLauncherShell(command)
    }

    private static func isLauncherShell(_ command: String) -> Bool {
        !launcherScriptPath.isEmpty && command.contains(launcherScriptPath)
    }

    private static func parentPID(for pid: Int32, in table: [ProcessRow]? = nil) -> Int32? {
        let rows = table ?? processTable()
        return rows.first(where: { $0.pid == pid })?.ppid
    }

    private static func launcherPath() -> String {
        let appSupportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupportRoot
            .appendingPathComponent("DevJourney", isDirectory: true)
            .appendingPathComponent("devjourney-mcp", isDirectory: false)
            .path
    }

    private static func processTable() -> [ProcessRow] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,command="]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output
            .split(separator: "\n")
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }

                let components = trimmed.split(maxSplits: 2, whereSeparator: \.isWhitespace)
                guard components.count == 3,
                      let pid = Int32(components[0]),
                      let ppid = Int32(components[1]) else {
                    return nil
                }

                return ProcessRow(pid: pid, ppid: ppid, command: String(components[2]))
            }
    }

    private struct ProcessRow {
        let pid: Int32
        let ppid: Int32
        let command: String
    }
}
