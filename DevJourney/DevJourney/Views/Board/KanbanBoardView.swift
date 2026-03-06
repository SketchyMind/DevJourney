import SwiftUI

enum ActivePanel: Equatable {
    case ticketCreation
    case clarification(Ticket)
    case review(Ticket)
    case agentWorking(Ticket)
    case history(Ticket)

    static func == (lhs: ActivePanel, rhs: ActivePanel) -> Bool {
        switch (lhs, rhs) {
        case (.ticketCreation, .ticketCreation):
            return true
        case (.clarification(let a), .clarification(let b)):
            return a.id == b.id
        case (.review(let a), .review(let b)):
            return a.id == b.id
        case (.agentWorking(let a), .agentWorking(let b)):
            return a.id == b.id
        case (.history(let a), .history(let b)):
            return a.id == b.id
        default:
            return false
        }
    }
}

struct KanbanBoardView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSettings = false
    @State private var activePanel: ActivePanel? = nil

    private var isPanelOpen: Bool { activePanel != nil }

    private var boardStages: [Stage] {
        Stage.allCases.filter { $0 != .complete }
    }

    var body: some View {
        ZStack {
            Color.bgApp.ignoresSafeArea()

            VStack(spacing: 0) {
                TopBarView(onSettingsTapped: { showSettings.toggle() })

                GeometryReader { geometry in
                    let columnSpacing: CGFloat = 10
                    let horizontalPadding: CGFloat = Spacing.lg * 2
                    let totalSpacingWidth: CGFloat = columnSpacing * CGFloat(boardStages.count - 1)
                    let columnWidth: CGFloat = (geometry.size.width - horizontalPadding - totalSpacingWidth) / CGFloat(boardStages.count)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: columnSpacing) {
                            ForEach(boardStages, id: \.self) { stage in
                                KanbanColumnView(
                                    stage: stage,
                                    onAddTicket: { handleAddTicket(stage: stage) },
                                    onStartTicket: { handleStartTicket($0) },
                                    onStartStage: { handleStartStage($0) },
                                    onStopStage: { handleStopStage($0) },
                                    onClarify: { handleClarify($0) },
                                    onReview: { handleReview($0) },
                                    onComplete: { handleComplete($0) },
                                    onShowHistory: { handleShowHistory($0) }
                                )
                                .frame(width: columnWidth)
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.xl)
                    }
                }

                StatusBarView()
            }

            // Panel overlay
            if isPanelOpen {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture { dismissPanel() }
                    .transition(.opacity)

                panelContent
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPanelOpen)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(appState)
        }
        .onAppear {
            appState.loadProjectTickets()
        }
        .environmentObject(appState)
    }

    // MARK: - Panel Content

    @ViewBuilder
    private var panelContent: some View {
        switch activePanel {
        case .ticketCreation:
            TicketCreationPanel(isPresented: panelBinding)
                .environmentObject(appState)

        case .clarification(let ticket):
            ClarificationPanel(isPresented: panelBinding, ticket: ticket)
                .environmentObject(appState)

        case .review(let ticket):
            ReviewPanel(isPresented: panelBinding, ticket: ticket)
                .environmentObject(appState)

        case .agentWorking(let ticket):
            DesignAgentPanel(isPresented: panelBinding, ticket: ticket)
                .environmentObject(appState)

        case .history(let ticket):
            TicketHistoryPanel(isPresented: panelBinding, ticket: ticket)

        case .none:
            EmptyView()
        }
    }

    private var panelBinding: Binding<Bool> {
        Binding(
            get: { isPanelOpen },
            set: { if !$0 { dismissPanel() } }
        )
    }

    private func dismissPanel() {
        withAnimation(.easeInOut(duration: 0.25)) {
            activePanel = nil
        }
    }

    // MARK: - Actions

    private func handleAddTicket(stage: Stage) {
        withAnimation(.easeInOut(duration: 0.25)) {
            activePanel = .ticketCreation
        }
    }

    private func handleStartTicket(_ ticket: Ticket) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            ticket.setStatus(.ready)
            ticket.setStage(.planning)
        }
    }

    private func handleStartStage(_ ticket: Ticket) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            activePanel = .agentWorking(ticket)
        }
        appState.startAgent(for: ticket)
    }

    private func handleStopStage(_ ticket: Ticket) {
        appState.stopAgent(for: ticket.id)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            activePanel = nil
        }
    }

    private func handleClarify(_ ticket: Ticket) {
        withAnimation(.easeInOut(duration: 0.25)) {
            activePanel = .clarification(ticket)
        }
    }

    private func handleReview(_ ticket: Ticket) {
        withAnimation(.easeInOut(duration: 0.25)) {
            activePanel = .review(ticket)
        }
    }

    private func handleShowHistory(_ ticket: Ticket) {
        withAnimation(.easeInOut(duration: 0.25)) {
            activePanel = .history(ticket)
        }
    }

    private func handleComplete(_ ticket: Ticket) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            ticket.setStage(.complete)
            ticket.setStatus(.complete)
        }
    }
}
