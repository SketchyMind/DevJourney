import SwiftUI

struct ClarificationPanel: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    let ticket: Ticket

    @State private var answerInputs: [String: String] = [:]

    private var unanswered: [ClarificationItem] {
        ticket.clarifications.filter { $0.answer == nil }
    }

    private var answered: [ClarificationItem] {
        ticket.clarifications.filter { $0.answer != nil }
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
                    Text("No clarification questions yet.")
                        .font(Typography.bodyMedium)
                        .foregroundColor(.textMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Spacing.xxl)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.gapLg) {
                            // Unanswered questions
                            if !unanswered.isEmpty {
                                Text("Needs Your Input")
                                    .font(Typography.labelMedium)
                                    .foregroundColor(.accentYellow)

                                ForEach(unanswered, id: \.id) { item in
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
                            Text("Resume Agent")
                        }
                        .font(Typography.labelLarge)
                        .foregroundColor(unanswered.isEmpty ? .bgApp : .textMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: Spacing.buttonHeight)
                        .background(unanswered.isEmpty ? Color.accentGreen : Color.bgElevated)
                        .cornerRadius(Spacing.radiusMd)
                    }
                    .buttonStyle(.plain)
                    .disabled(!unanswered.isEmpty)
                }
            }
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
        item.answer(text)
        answerInputs.removeValue(forKey: item.id)
    }

    private func resumeAgent() {
        // Collect all answers into a single string for the agent
        let allAnswers = ticket.clarifications
            .compactMap { item -> String? in
                guard let answer = item.answer else { return nil }
                return "Q: \(item.question)\nA: \(answer)"
            }
            .joined(separator: "\n\n")

        ticket.setStatus(.active)
        appState.resumeAgent(for: ticket, answer: allAnswers)
        isPresented = false
    }
}
