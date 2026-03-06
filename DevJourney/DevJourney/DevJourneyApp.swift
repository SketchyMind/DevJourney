import SwiftUI
import SwiftData
import Combine
#if canImport(AppKit)
import AppKit
#endif

@main
struct DevJourneyApp: App {
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if appState.currentProject != nil {
                    KanbanBoardView()
                        .environmentObject(appState)
                } else {
                    UnifiedOnboardingView()
                        .environmentObject(appState)
                }
            }
            .onAppear {
                #if canImport(AppKit)
                NSApp.activate()
                #endif
            }
        }
        .modelContainer(appState.modelContainer)
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var currentProject: Project?
    @Published var tickets: [Ticket] = []
    @Published var activeSessions: [String: AgentSession] = [:]
    @Published var providerStatuses: [AIProvider: Bool] = [:]
    @Published var currentBranch: String = "main"
    @Published var branchIsDirty: Bool = false

    let modelContainer: ModelContainer
    let projectService: ProjectService
    let gitHubService = GitHubService()
    let fileService = FileService()
    let orchestrator: AgentOrchestrator
    private var cancellables = Set<AnyCancellable>()

    init() {
        do {
            let schema = Schema([Project.self, Ticket.self, AgentSession.self, ClarificationItem.self, ReviewResult.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.projectService = ProjectService(modelContainer: modelContainer)
            self.orchestrator = AgentOrchestrator(modelContext: modelContainer.mainContext, gitHubService: gitHubService)
            orchestrator.$activeSessions
                .receive(on: RunLoop.main)
                .sink { [weak self] sessions in
                    self?.activeSessions = sessions
                }
                .store(in: &cancellables)

            // Migrate API keys from UserDefaults to Keychain
            KeychainService.shared.migrateFromUserDefaults()
            refreshProviderStatuses()
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    func loadProjectTickets() {
        guard let project = currentProject else {
            tickets = []
            return
        }
        tickets = projectService.getProjectTickets(projectId: project.id)
    }

    func selectProject(_ project: Project) {
        currentProject = project
        loadProjectTickets()
        Task { await refreshBranchInfo() }
    }

    func startAgent(for ticket: Ticket) {
        guard let project = currentProject else { return }
        orchestrator.dispatchTicket(ticket, project: project)
    }

    func stopAgent(for ticketId: String) {
        orchestrator.stopAgent(ticketId: ticketId)
    }

    func resumeAgent(for ticket: Ticket, answer: String) {
        guard let project = currentProject else { return }
        orchestrator.resumeAfterClarification(ticket, project: project, answer: answer)
    }

    func refreshProviderStatuses() {
        for provider in AIProvider.allCases {
            providerStatuses[provider] = KeychainService.shared.isProviderConnected(provider)
        }
    }

    func refreshBranchInfo() async {
        guard let project = currentProject else { return }
        let path = URL(fileURLWithPath: project.folderPath)
        let branch = await gitHubService.runGitAsync(at: path, args: ["rev-parse", "--abbrev-ref", "HEAD"]) ?? "main"
        let status = await gitHubService.runGitAsync(at: path, args: ["status", "--porcelain"])
        self.currentBranch = branch
        self.branchIsDirty = !(status?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
