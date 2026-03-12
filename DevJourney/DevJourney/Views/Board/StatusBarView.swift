import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var appState: AppState

    private var activeAgentCount: Int {
        appState.activeSessions.count
    }

    private var totalTickets: Int {
        appState.tickets.count
    }

    private var blockedTickets: Int {
        appState.tickets.filter {
            $0.handoverStateEnum == .blocked || $0.statusEnum == .clarify
        }.count
    }

    private var completedTickets: Int {
        appState.tickets.filter { $0.statusEnum == .complete }.count
    }

    private var configuredProviderCount: Int {
        guard let project = appState.currentProject else { return 0 }
        return project.providerConfigs.filter {
            $0.enabled && KeychainService.shared.readProviderAPIKey(reference: $0.apiKeyReference) != nil
        }.count
    }

    private var mcpConnected: Bool {
        appState.mcpConnectionStatus.isClientConnected()
    }

    private var claudeMCPReady: Bool {
        appState.claudeMCPRegistrationStatus.isReadyForLocalProjectStore
    }

    var body: some View {
        HStack(spacing: Spacing.gapXl) {
            // Left: Connection status
            HStack(spacing: Spacing.gapXs) {
                Circle()
                    .fill(configuredProviderCount > 0 ? Color.accentGreen : Color.accentYellow)
                    .frame(width: 6, height: 6)

                Text(configuredProviderCount > 0 ? "\(configuredProviderCount) Providers Ready" : "Provider Setup Needed")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
            }

            HStack(spacing: Spacing.gapXs) {
                Circle()
                    .fill((mcpConnected || claudeMCPReady) ? Color.accentGreen : Color.textMuted)
                    .frame(width: 6, height: 6)

                Text(
                    mcpConnected
                    ? "\(appState.mcpConnectionStatus.displayClientName) via MCP"
                    : (claudeMCPReady ? "Claude MCP Ready" : "No MCP client")
                )
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

                if blockedTickets > 0 {
                    HStack(spacing: Spacing.gapXs) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundColor(.accentYellow)
                        Text("\(blockedTickets) blocked")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
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
