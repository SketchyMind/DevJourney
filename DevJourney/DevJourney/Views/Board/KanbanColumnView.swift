import SwiftUI

struct KanbanColumnView: View {
    @EnvironmentObject var appState: AppState
    let stage: Stage
    var onAddTicket: () -> Void = {}
    var onOpenDetails: (Ticket) -> Void = { _ in }
    var onStartTicket: (Ticket) -> Void = { _ in }
    var onStartStage: (Ticket) -> Void = { _ in }
    var onStopStage: (Ticket) -> Void = { _ in }
    var onClarify: (Ticket) -> Void = { _ in }
    var onReview: (Ticket) -> Void = { _ in }
    var onComplete: (Ticket) -> Void = { _ in }
    var onShowHistory: (Ticket) -> Void = { _ in }

    private var stageTickets: [Ticket] {
        appState.tickets.filter { $0.stageEnum == stage }
    }

    private var isLastColumn: Bool { stage == .debug }

    private var stageColor: Color {
        Color.clear.colorForStage(stage)
    }

    var body: some View {
        VStack(spacing: 10) {
            ColumnHeaderView(
                stage: stage,
                ticketCount: stageTickets.count,
                totalTickets: appState.tickets.count
            )

            if stage == .backlog {
                AddButtonView(stage: stage, onAdd: onAddTicket)
            }

            if stageTickets.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(stageTickets, id: \.id) { ticket in
                            TicketCardView(
                                ticket: ticket,
                                onOpenDetails: { onOpenDetails(ticket) },
                                onStartTicket: { onStartTicket(ticket) },
                                onStartStage: { onStartStage(ticket) },
                                onStopStage: { onStopStage(ticket) },
                                onClarify: { onClarify(ticket) },
                                onReview: { onReview(ticket) },
                                onComplete: { onComplete(ticket) },
                                onShowHistory: { onShowHistory(ticket) }
                            )
                            .padding(.horizontal, 2)
                            .padding(.top, 2)
                            .padding(.bottom, 14)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.95).combined(with: .opacity),
                                removal: .scale(scale: 0.95).combined(with: .opacity)
                            ))
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 2)
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(.vertical, 0)
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(
            Rectangle()
                .fill(isLastColumn ? Color.clear : Color.borderSubtle)
                .frame(width: 1),
            alignment: .trailing
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: stageTickets.count)
    }

    @ViewBuilder
    private var emptyState: some View {
        if stage != .backlog {
            VStack(spacing: Spacing.sm) {
                Image(systemName: emptyStateIcon)
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.textMuted.opacity(0.5))
                Text("No tickets")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textMuted.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: Spacing.radiusMd)
                    .fill(Color.emptyStateBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusMd)
                    .strokeBorder(Color.borderSubtle.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
        }
    }

    private var emptyStateIcon: String {
        switch stage {
        case .planning: return "list.bullet.clipboard"
        case .design: return "paintbrush"
        case .dev: return "chevron.left.forwardslash.chevron.right"
        case .debug: return "ant"
        default: return "tray"
        }
    }
}
