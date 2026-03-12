import SwiftUI

struct ClarificationPanel: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    let ticket: Ticket

    @State private var answerInputs: [String: String] = [:]

    private var unanswered: [ClarificationItem] {
        ticket.clarifications.filter { $0.answer == nil }
    }

    private var inlineReviewFeedback: [ClarificationItem] {
        unanswered.filter(isInlineReviewFeedback)
    }

    private var manualUnanswered: [ClarificationItem] {
        unanswered.filter { !isInlineReviewFeedback($0) }
    }

    private var answered: [ClarificationItem] {
        ticket.clarifications.filter { $0.answer != nil }
    }

    private var blockedReason: String? {
        let trimmed = ticket.blockedReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var mcpPromptName: String? {
        switch ticket.stageEnum {
        case .planning:
            return "planning_agent"
        case .design:
            return "design_agent"
        case .dev:
            return "dev_agent"
        case .debug:
            return "debug_agent"
        case .backlog, .complete:
            return nil
        }
    }

    var body: some View {
        PanelContainer(title: "Clarifications", isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: Spacing.gapLg) {
                // Ticket context
                VStack(alignment: .leading, spacing: Spacing.gapXs) {
                    Text(ticket.title)
                        .font(Typography.headingSmall)
                        .foregroundColor(.textPrimary)
                    Text(ticket.stageEnum.displayName)
                        .font(Typography.captionLarge)
                        .foregroundColor(.textSecondary)
                }

                Divider().background(Color.borderSubtle)

                if unanswered.isEmpty && answered.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.gapMd) {
                        if let blockedReason {
                            VStack(alignment: .leading, spacing: Spacing.gapSm) {
                                Text("Blocked")
                                    .font(Typography.labelMedium)
                                    .foregroundColor(.accentYellow)
                                Text(blockedReason)
                                    .font(Typography.bodyMedium)
                                    .foregroundColor(.textPrimary)
                            }
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.bgElevated)
                            .cornerRadius(Spacing.radiusMd)
                        } else {
                            Text("No clarification questions yet.")
                                .font(Typography.bodyMedium)
                                .foregroundColor(.textMuted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, Spacing.xxl)
                        }

                        if (appState.mcpConnectionStatus.isClientConnected()
                            || appState.claudeMCPRegistrationStatus.isReadyForLocalProjectStore),
                           let mcpPromptName,
                           blockedReason?.localizedCaseInsensitiveContains("provider") == true {
                            VStack(alignment: .leading, spacing: Spacing.gapSm) {
                                Text("MCP Next Step")
                                    .font(Typography.labelMedium)
                                    .foregroundColor(.accentPurple)
                                Text("Claude MCP is ready, but stage work does not start automatically from the board. In Claude Code, ask it to run the `\(mcpPromptName)` prompt for ticket `\(ticket.id)`, or configure an in-app provider in Settings.")
                                    .font(Typography.bodySmall)
                                    .foregroundColor(.textSecondary)
                            }
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.accentPurpleDim)
                            .cornerRadius(Spacing.radiusMd)
                        }
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.gapLg) {
                            // Unanswered questions
                            if !manualUnanswered.isEmpty {
                                Text("Needs Your Input")
                                    .font(Typography.labelMedium)
                                    .foregroundColor(.accentYellow)

                                ForEach(manualUnanswered, id: \.id) { item in
                                    VStack(alignment: .leading, spacing: Spacing.gapSm) {
                                        HStack(alignment: .top, spacing: Spacing.gapSm) {
                                            Image(systemName: "questionmark.circle.fill")
                                                .foregroundColor(.accentYellow)
                                                .font(.system(size: Spacing.iconSmall))
                                            Text(item.question)
                                                .font(Typography.bodyMedium)
                                                .foregroundColor(.textPrimary)
                                        }

                                        HStack(spacing: Spacing.gapSm) {
                                            TextField("Type your answer...", text: binding(for: item.id))
                                                .textFieldStyle(.plain)
                                                .font(Typography.bodySmall)
                                                .foregroundColor(.textPrimary)
                                                .padding(Spacing.sm)
                                                .background(Color.bgApp)
                                                .cornerRadius(Spacing.radiusSm)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: Spacing.radiusSm)
                                                        .stroke(Color.borderSubtle, lineWidth: 1)
                                                )

                                            Button {
                                                submitAnswer(item)
                                            } label: {
                                                Image(systemName: "paperplane.fill")
                                                    .foregroundColor(.accentPurple)
                                                    .font(.system(size: 14))
                                            }
                                            .buttonStyle(.plain)
                                            .disabled((answerInputs[item.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                                        }
                                    }
                                    .padding(Spacing.md)
                                    .background(Color.bgElevated)
                                    .cornerRadius(Spacing.radiusMd)
                                }
                            }

                            if !inlineReviewFeedback.isEmpty {
                                Text("Applying Review Feedback")
                                    .font(Typography.labelMedium)
                                    .foregroundColor(.accentPurple)

                                ForEach(inlineReviewFeedback, id: \.id) { item in
                                    VStack(alignment: .leading, spacing: Spacing.gapSm) {
                                        HStack(alignment: .top, spacing: Spacing.gapSm) {
                                            Image(systemName: "arrow.trianglehead.clockwise")
                                                .foregroundColor(.accentPurple)
                                                .font(.system(size: Spacing.iconSmall))
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(extractedInlineReviewFeedback(from: item) ?? item.question)
                                                    .font(Typography.bodyMedium)
                                                    .foregroundColor(.textPrimary)
                                                Text("This change request was already provided in the review step. DevJourney will reuse it automatically.")
                                                    .font(Typography.captionLarge)
                                                    .foregroundColor(.textSecondary)
                                            }
                                        }
                                    }
                                    .padding(Spacing.md)
                                    .background(Color.accentPurpleDim)
                                    .cornerRadius(Spacing.radiusMd)
                                }
                            }

                            // Answered questions
                            if !answered.isEmpty {
                                Text("Answered")
                                    .font(Typography.labelMedium)
                                    .foregroundColor(.textMuted)

                                ForEach(answered, id: \.id) { item in
                                    VStack(alignment: .leading, spacing: Spacing.gapSm) {
                                        HStack(alignment: .top, spacing: Spacing.gapSm) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.accentGreen)
                                                .font(.system(size: Spacing.iconSmall))
                                            Text(item.question)
                                                .font(Typography.bodyMedium)
                                                .foregroundColor(.textSecondary)
                                        }
                                        if let answer = item.answer {
                                            Text(answer)
                                                .font(Typography.bodySmall)
                                                .foregroundColor(.textPrimary)
                                                .padding(.leading, Spacing.iconSmall + Spacing.gapSm)
                                        }
                                    }
                                    .padding(Spacing.md)
                                    .background(Color.bgCard)
                                    .cornerRadius(Spacing.radiusMd)
                                }
                            }
                        }
                    }
                }

                Spacer()

                // Resume Agent button (enabled when all questions answered)
                if !ticket.clarifications.isEmpty {
                    Button {
                        resumeAgent()
                    } label: {
                        HStack(spacing: Spacing.gapSm) {
                            Image(systemName: "play.fill")
                            Text(inlineReviewFeedback.isEmpty ? "Resume Agent" : "Apply Changes and Resume")
                        }
                        .font(Typography.labelLarge)
                        .foregroundColor(manualUnanswered.isEmpty ? .bgApp : .textMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: Spacing.buttonHeight)
                        .background(manualUnanswered.isEmpty ? Color.accentGreen : Color.bgElevated)
                        .cornerRadius(Spacing.radiusMd)
                    }
                    .buttonStyle(.plain)
                    .disabled(!manualUnanswered.isEmpty)
                }
            }
        }
        .onAppear {
            appState.resolveClarificationsIfPossible(for: ticket)
            applyInlineReviewFeedbackIfPossible()
            autoResumeRecoveredReviewRequestIfPossible()
        }
    }

    private func binding(for id: String) -> Binding<String> {
        Binding(
            get: { answerInputs[id] ?? "" },
            set: { answerInputs[id] = $0 }
        )
    }

    private func submitAnswer(_ item: ClarificationItem) {
        guard let text = answerInputs[item.id], !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        appState.answerClarification(item, for: ticket, response: text)
        answerInputs.removeValue(forKey: item.id)
        if ticket.pendingClarificationCount == 0 {
            isPresented = false
        }
    }

    private func resumeAgent() {
        applyInlineReviewFeedbackIfPossible()
        appState.resumeStage(for: ticket)
        isPresented = false
    }

    private func autoResumeRecoveredReviewRequestIfPossible() {
        guard manualUnanswered.isEmpty,
              ticket.handoverStateEnum == .returned,
              answered.contains(where: {
                  $0.stage == ticket.stage && $0.question.localizedCaseInsensitiveContains("Review requested changes")
              }) else {
            return
        }

        appState.resumeStage(for: ticket)
        isPresented = false
    }

    private func applyInlineReviewFeedbackIfPossible() {
        for item in inlineReviewFeedback {
            guard let feedback = extractedInlineReviewFeedback(from: item), !feedback.isEmpty else {
                continue
            }
            appState.answerClarification(item, for: ticket, response: feedback)
        }
    }

    private func isInlineReviewFeedback(_ item: ClarificationItem) -> Bool {
        item.question.localizedCaseInsensitiveContains("Review requested changes:")
    }

    private func extractedInlineReviewFeedback(from item: ClarificationItem) -> String? {
        let prefix = "Review requested changes:"
        guard let range = item.question.range(of: prefix, options: .caseInsensitive) else {
            return nil
        }
        let feedback = item.question[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return feedback.isEmpty ? nil : feedback
    }
}
