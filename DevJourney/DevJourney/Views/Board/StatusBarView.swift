import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var appState: AppState

    private var activeAgentCount: Int {
        appState.activeSessions.count
    }

    private var totalTickets: Int {
        appState.tickets.count
    }

    private var completedTickets: Int {
        appState.tickets.filter { $0.statusEnum == .complete }.count
    }

    var body: some View {
        HStack(spacing: Spacing.gapXl) {
            // Left: Connection status
            HStack(spacing: Spacing.gapXs) {
                Circle()
                    .fill(Color.accentGreen)
                    .frame(width: 6, height: 6)

                Text("Connected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
            }

            // Ticket stats
            if totalTickets > 0 {
                HStack(spacing: Spacing.gapXs) {
                    Image(systemName: "ticket")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.textMuted)
                    Text("\(completedTickets)/\(totalTickets) tickets")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            // Right: Agent info + version
            HStack(spacing: Spacing.gapXl) {
                if activeAgentCount > 0 {
                    HStack(spacing: Spacing.gapXs) {
                        PulsingDot(color: .accentGreen)

                        Text("\(activeAgentCount) Agent\(activeAgentCount == 1 ? "" : "s") Active")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                }

                Text("v0.1.0")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.textMuted)
            }
        }
        .frame(height: 32)
        .padding(.horizontal, Spacing.lg)
        .background(Color.bgSurface)
        .overlay(
            Rectangle()
                .fill(Color.borderSubtle)
                .frame(height: 1),
            alignment: .top
        )
    }
}
