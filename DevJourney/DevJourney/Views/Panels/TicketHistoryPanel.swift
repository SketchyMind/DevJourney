import SwiftUI

struct TicketHistoryPanel: View {
    @Binding var isPresented: Bool
    let ticket: Ticket

    private var sortedSessions: [AgentSession] {
        ticket.sessions.sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        PanelContainer(title: "History", isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: Spacing.gapLg) {
                // Ticket info
                VStack(alignment: .leading, spacing: Spacing.gapXs) {
                    Text(ticket.title)
                        .font(Typography.headingSmall)
                        .foregroundColor(.textPrimary)
                    HStack(spacing: Spacing.gapSm) {
                        Text(ticket.stageEnum.displayName)
                            .font(Typography.captionLarge)
                            .foregroundColor(.textSecondary)
                        Text("--")
                            .foregroundColor(.textMuted)
                        Text("\(ticket.sessions.count) session\(ticket.sessions.count == 1 ? "" : "s")")
                            .font(Typography.captionLarge)
                            .foregroundColor(.textMuted)
                    }
                }

                Divider().background(Color.borderSubtle)

                if sortedSessions.isEmpty {
                    VStack(spacing: Spacing.gapMd) {
                        Image(systemName: "clock")
                            .font(.system(size: 32))
                            .foregroundColor(.textMuted)
                        Text("No sessions yet")
                            .font(Typography.bodyMedium)
                            .foregroundColor(.textMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.gapMd) {
                            ForEach(sortedSessions, id: \.id) { session in
                                SessionCard(session: session)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct SessionCard: View {
    let session: AgentSession
    @State private var isExpanded = false

    private var stageName: String {
        Stage(rawValue: session.stage)?.displayName ?? session.stage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.gapSm) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stageName)
                            .font(Typography.labelMedium)
                            .foregroundColor(.textPrimary)
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                    }
                    Spacer()
                    HStack(spacing: Spacing.gapSm) {
                        Text("\(session.durationSeconds)s")
                            .font(Typography.captionLarge)
                            .foregroundColor(.textSecondary)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(.textMuted)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: Spacing.gapSm) {
                    // Model
                    HStack(spacing: Spacing.gapSm) {
                        Text("Model:")
                            .font(Typography.captionLarge)
                            .foregroundColor(.textMuted)
                        Text(session.modelUsed)
                            .font(Typography.code)
                            .foregroundColor(.textSecondary)
                    }

                    // Result summary
                    if !session.resultSummary.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.gapXs) {
                            Text("Results")
                                .font(Typography.labelSmall)
                                .foregroundColor(.textMuted)
                            ForEach(session.resultSummary, id: \.self) { point in
                                HStack(alignment: .top, spacing: Spacing.gapXs) {
                                    Text("-")
                                        .foregroundColor(.textMuted)
                                    Text(point)
                                        .font(Typography.bodySmall)
                                        .foregroundColor(.textPrimary)
                                }
                            }
                        }
                    }

                    // Files changed
                    if !session.filesChanged.isEmpty {
                        HStack(spacing: Spacing.gapSm) {
                            Image(systemName: "doc.text")
                                .foregroundColor(.textMuted)
                                .font(.system(size: 12))
                            Text("\(session.filesChanged.count) files changed")
                                .font(Typography.captionLarge)
                                .foregroundColor(.textSecondary)
                            if session.commitCount > 0 {
                                Text("-")
                                    .foregroundColor(.textMuted)
                                Text("\(session.commitCount) commits")
                                    .font(Typography.captionLarge)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                    }

                    // Dialog preview
                    if !session.dialog.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.gapXs) {
                            Text("Dialog (\(session.dialog.count) messages)")
                                .font(Typography.labelSmall)
                                .foregroundColor(.textMuted)
                            ForEach(session.dialog.prefix(4), id: \.timestamp) { entry in
                                HStack(alignment: .top, spacing: Spacing.gapXs) {
                                    Text(entry.role == "user" ? "You:" : "AI:")
                                        .font(Typography.captionLarge)
                                        .foregroundColor(entry.role == "user" ? .accentBlue : .accentPurple)
                                        .frame(width: 28, alignment: .leading)
                                    Text(entry.content)
                                        .font(Typography.captionLarge)
                                        .foregroundColor(.textSecondary)
                                        .lineLimit(2)
                                }
                            }
                            if session.dialog.count > 4 {
                                Text("+ \(session.dialog.count - 4) more...")
                                    .font(Typography.captionSmall)
                                    .foregroundColor(.textMuted)
                            }
                        }
                    }
                }
                .padding(.top, Spacing.gapXs)
            }
        }
        .padding(Spacing.md)
        .background(Color.bgElevated)
        .cornerRadius(Spacing.radiusMd)
    }
}
