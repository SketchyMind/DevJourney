import SwiftUI
import SwiftData

struct ReviewPanel: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    let ticket: Ticket

    @State private var reviewerComment = ""

    private var latestSession: AgentSession? {
        ticket.sessions
            .filter { $0.stage == ticket.stage }
            .sorted { $0.startedAt > $1.startedAt }
            .first
    }

    var body: some View {
        PanelContainer(title: "Review Results", isPresented: $isPresented) {
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
                        if let session = latestSession {
                            Text("--")
                                .foregroundColor(.textMuted)
                            Text("\(session.durationSeconds)s")
                                .font(Typography.captionLarge)
                                .foregroundColor(.textMuted)
                        }
                    }
                }

                Divider().background(Color.borderSubtle)

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.gapLg) {
                        // Result summary
                        if let session = latestSession, !session.resultSummary.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.gapSm) {
                                Text("Summary")
                                    .font(Typography.labelMedium)
                                    .foregroundColor(.textSecondary)
                                ForEach(session.resultSummary, id: \.self) { point in
                                    HStack(alignment: .top, spacing: Spacing.gapSm) {
                                        Circle()
                                            .fill(Color.accentPurple)
                                            .frame(width: 6, height: 6)
                                            .padding(.top, 6)
                                        Text(point)
                                            .font(Typography.bodyMedium)
                                            .foregroundColor(.textPrimary)
                                    }
                                }
                            }
                        }

                        // Files changed
                        if let session = latestSession, !session.filesChanged.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.gapSm) {
                                Text("Files Changed (\(session.filesChanged.count))")
                                    .font(Typography.labelMedium)
                                    .foregroundColor(.textSecondary)
                                ForEach(session.filesChanged, id: \.path) { file in
                                    HStack(spacing: Spacing.gapSm) {
                                        Image(systemName: iconForFileStatus(file.status))
                                            .foregroundColor(colorForFileStatus(file.status))
                                            .font(.system(size: 12))
                                        Text(file.path)
                                            .font(Typography.code)
                                            .foregroundColor(.textPrimary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                        Text("+\(file.additions) -\(file.deletions)")
                                            .font(Typography.captionSmall)
                                            .foregroundColor(.textMuted)
                                    }
                                    .padding(.vertical, Spacing.xs)
                                }
                            }
                        }

                        // Commit count
                        if let session = latestSession, session.commitCount > 0 {
                            HStack(spacing: Spacing.gapSm) {
                                Image(systemName: "arrow.triangle.branch")
                                    .foregroundColor(.textMuted)
                                Text("\(session.commitCount) commit\(session.commitCount == 1 ? "" : "s")")
                                    .font(Typography.bodySmall)
                                    .foregroundColor(.textSecondary)
                            }
                        }

                        // Reviewer comment
                        VStack(alignment: .leading, spacing: Spacing.gapXs) {
                            Text("Comment (optional)")
                                .font(Typography.labelMedium)
                                .foregroundColor(.textSecondary)
                            TextEditor(text: $reviewerComment)
                                .font(Typography.bodySmall)
                                .foregroundColor(.textPrimary)
                                .scrollContentBackground(.hidden)
                                .padding(Spacing.sm)
                                .frame(minHeight: 80)
                                .background(Color.bgApp)
                                .cornerRadius(Spacing.radiusSm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Spacing.radiusSm)
                                        .stroke(Color.borderSubtle, lineWidth: 1)
                                )
                        }
                    }
                }

                Spacer()

                // Action buttons
                VStack(spacing: Spacing.gapSm) {
                    if let nextStage = ticket.stageEnum.nextStage() {
                        Button {
                            approve(nextStage: nextStage)
                        } label: {
                            HStack(spacing: Spacing.gapSm) {
                                Image(systemName: "checkmark")
                                Text("Pass to \(nextStage.displayName)")
                            }
                            .font(Typography.labelLarge)
                            .foregroundColor(.bgApp)
                            .frame(maxWidth: .infinity)
                            .frame(height: Spacing.buttonHeight)
                            .background(Color.accentGreen)
                            .cornerRadius(Spacing.radiusMd)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        requestChanges()
                    } label: {
                        HStack(spacing: Spacing.gapSm) {
                            Image(systemName: "arrow.uturn.backward")
                            Text("Request Changes")
                        }
                        .font(Typography.labelLarge)
                        .foregroundColor(.accentOrange)
                        .frame(maxWidth: .infinity)
                        .frame(height: Spacing.buttonHeight)
                        .background(Color.accentOrangeDim)
                        .cornerRadius(Spacing.radiusMd)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func approve(nextStage: Stage) {
        let result = ReviewResult(
            ticketId: ticket.id,
            stage: ticket.stage,
            approved: true
        )
        if !reviewerComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.setComment(reviewerComment)
        }
        modelContext.insert(result)
        ticket.reviewResults.append(result)
        ticket.setStage(nextStage)
        ticket.setStatus(.ready)
        isPresented = false
    }

    private func requestChanges() {
        let result = ReviewResult(
            ticketId: ticket.id,
            stage: ticket.stage,
            approved: false
        )
        if !reviewerComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.setComment(reviewerComment)
        }
        modelContext.insert(result)
        ticket.reviewResults.append(result)
        ticket.setStatus(.ready)
        isPresented = false
    }

    private func iconForFileStatus(_ status: String) -> String {
        switch status {
        case "created": return "plus.circle.fill"
        case "deleted": return "minus.circle.fill"
        default: return "pencil.circle.fill"
        }
    }

    private func colorForFileStatus(_ status: String) -> Color {
        switch status {
        case "created": return .accentGreen
        case "deleted": return .accentRed
        default: return .accentBlue
        }
    }
}
