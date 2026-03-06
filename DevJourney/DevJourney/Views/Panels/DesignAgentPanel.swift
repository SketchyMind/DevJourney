import SwiftUI

struct DesignAgentPanel: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    let ticket: Ticket

    private var activeSession: AgentSession? {
        appState.activeSessions[ticket.id]
    }

    var body: some View {
        PanelContainer(title: "Agent Working", isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: Spacing.gapLg) {
                // Ticket + stage
                VStack(alignment: .leading, spacing: Spacing.gapXs) {
                    Text(ticket.title)
                        .font(Typography.headingSmall)
                        .foregroundColor(.textPrimary)
                    HStack(spacing: Spacing.gapSm) {
                        Circle()
                            .fill(Color.accentGreen)
                            .frame(width: 8, height: 8)
                        Text(ticket.stageEnum.displayName)
                            .font(Typography.captionLarge)
                            .foregroundColor(.accentGreen)
                        if let session = activeSession {
                            Text("-- \(session.modelUsed)")
                                .font(Typography.captionSmall)
                                .foregroundColor(.textMuted)
                        }
                    }
                }

                Divider().background(Color.borderSubtle)

                // Live thoughts stream
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.gapSm) {
                            if let session = activeSession {
                                // Thoughts
                                if !session.thoughts.isEmpty {
                                    Text("Thoughts")
                                        .font(Typography.labelSmall)
                                        .foregroundColor(.textMuted)
                                    ForEach(Array(session.thoughts.enumerated()), id: \.offset) { index, thought in
                                        ThoughtBubble(text: thought)
                                            .id("thought-\(index)")
                                    }
                                }

                                // Dialog
                                if !session.dialog.isEmpty {
                                    Text("Dialog")
                                        .font(Typography.labelSmall)
                                        .foregroundColor(.textMuted)
                                        .padding(.top, Spacing.gapSm)
                                    ForEach(Array(session.dialog.enumerated()), id: \.offset) { index, entry in
                                        DialogBubble(entry: entry)
                                            .id("dialog-\(index)")
                                    }
                                }
                            } else {
                                VStack(spacing: Spacing.gapMd) {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.accentPurple)
                                    Text("Waiting for agent to start...")
                                        .font(Typography.bodySmall)
                                        .foregroundColor(.textMuted)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.xxl)
                            }
                        }
                    }
                    .onChange(of: activeSession?.thoughts.count) { _, _ in
                        if let count = activeSession?.thoughts.count, count > 0 {
                            withAnimation {
                                proxy.scrollTo("thought-\(count - 1)", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: activeSession?.dialog.count) { _, _ in
                        if let count = activeSession?.dialog.count, count > 0 {
                            withAnimation {
                                proxy.scrollTo("dialog-\(count - 1)", anchor: .bottom)
                            }
                        }
                    }
                }

                Spacer()

                // Stop agent button
                Button {
                    stopAgent()
                } label: {
                    HStack(spacing: Spacing.gapSm) {
                        Image(systemName: "stop.fill")
                        Text("Stop Agent")
                    }
                    .font(Typography.labelLarge)
                    .foregroundColor(.accentRed)
                    .frame(maxWidth: .infinity)
                    .frame(height: Spacing.buttonHeight)
                    .background(Color.accentRedDim)
                    .cornerRadius(Spacing.radiusMd)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stopAgent() {
        appState.stopAgent(for: ticket.id)
        isPresented = false
    }
}

private struct ThoughtBubble: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.gapSm) {
            Image(systemName: "brain")
                .foregroundColor(.accentPurple)
                .font(.system(size: 12))
                .padding(.top, 2)
            Text(text)
                .font(Typography.bodySmall)
                .foregroundColor(.textSecondary)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentPurpleDim)
        .cornerRadius(Spacing.radiusSm)
    }
}

private struct DialogBubble: View {
    let entry: DialogEntry

    private var isUser: Bool { entry.role == "user" }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.gapSm) {
            Image(systemName: isUser ? "person.fill" : "cpu")
                .foregroundColor(isUser ? .accentBlue : .agentMechanic)
                .font(.system(size: 12))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(isUser ? "You" : "Agent")
                    .font(Typography.captionSmall)
                    .foregroundColor(isUser ? .accentBlue : .agentMechanic)
                Text(entry.content)
                    .font(Typography.bodySmall)
                    .foregroundColor(.textPrimary)
            }
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isUser ? Color.accentBlueDim : Color.agentMechanicDim)
        .cornerRadius(Spacing.radiusSm)
    }
}
