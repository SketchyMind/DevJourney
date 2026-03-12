import SwiftUI

struct TicketCreationPanel: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool

    @State private var title = ""
    @State private var description = ""
    @State private var priority: Priority = .medium
    @State private var tags: [String] = []
    @State private var tagInput = ""
    @State private var agentCount = 1

    var body: some View {
        PanelContainer(title: "Create Ticket", isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: Spacing.gapLg) {
                // Title
                VStack(alignment: .leading, spacing: Spacing.gapXs) {
                    Text("Title")
                        .font(Typography.labelMedium)
                        .foregroundColor(.textSecondary)
                    TextField("What needs to be done?", text: $title)
                        .textFieldStyle(.plain)
                        .font(Typography.bodyMedium)
                        .foregroundColor(.textPrimary)
                        .padding(Spacing.sm)
                        .background(Color.bgApp)
                        .cornerRadius(Spacing.radiusSm)
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.radiusSm)
                                .stroke(Color.borderSubtle, lineWidth: 1)
                        )
                }

                // Description
                VStack(alignment: .leading, spacing: Spacing.gapXs) {
                    Text("Description")
                        .font(Typography.labelMedium)
                        .foregroundColor(.textSecondary)
                    TextEditor(text: $description)
                        .font(Typography.bodyMedium)
                        .foregroundColor(.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(Spacing.sm)
                        .frame(minHeight: 120)
                        .background(Color.bgApp)
                        .cornerRadius(Spacing.radiusSm)
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.radiusSm)
                                .stroke(Color.borderSubtle, lineWidth: 1)
                        )
                }

                // Priority
                VStack(alignment: .leading, spacing: Spacing.gapXs) {
                    Text("Priority")
                        .font(Typography.labelMedium)
                        .foregroundColor(.textSecondary)
                    HStack(spacing: Spacing.gapSm) {
                        ForEach(Priority.allCases, id: \.self) { p in
                            Button {
                                priority = p
                            } label: {
                                Text(p.displayName)
                                    .font(Typography.labelSmall)
                                    .foregroundColor(priority == p ? .textPrimary : .textSecondary)
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, Spacing.xs)
                                    .background(priority == p ? Color.accentPurpleDim : Color.bgApp)
                                    .cornerRadius(Spacing.radiusSm)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Spacing.radiusSm)
                                            .stroke(priority == p ? Color.accentPurple : Color.borderSubtle, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Tags
                VStack(alignment: .leading, spacing: Spacing.gapXs) {
                    Text("Tags")
                        .font(Typography.labelMedium)
                        .foregroundColor(.textSecondary)
                    HStack(spacing: Spacing.gapSm) {
                        TextField("Add tag...", text: $tagInput)
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
                            .onSubmit { addTag() }
                        Button("Add") { addTag() }
                            .font(Typography.labelSmall)
                            .foregroundColor(.accentPurple)
                            .buttonStyle(.plain)
                            .disabled(tagInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if !tags.isEmpty {
                        FlowLayout(spacing: Spacing.gapXs) {
                            ForEach(tags, id: \.self) { tag in
                                HStack(spacing: Spacing.gapXs) {
                                    Text(tag)
                                        .font(Typography.captionLarge)
                                        .foregroundColor(.textPrimary)
                                    Button {
                                        tags.removeAll { $0 == tag }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.textMuted)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(Color.bgElevated)
                                .cornerRadius(Spacing.radiusXs)
                            }
                        }
                    }
                }

                // Agent Count
                VStack(alignment: .leading, spacing: Spacing.gapXs) {
                    Text("Agent Count")
                        .font(Typography.labelMedium)
                        .foregroundColor(.textSecondary)
                    HStack(spacing: Spacing.gapSm) {
                        ForEach(1...5, id: \.self) { count in
                            Button {
                                agentCount = count
                            } label: {
                                Text("\(count)")
                                    .font(Typography.labelSmall)
                                    .foregroundColor(agentCount == count ? .textPrimary : .textSecondary)
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, Spacing.xs)
                                    .background(agentCount == count ? Color.accentPurpleDim : Color.bgApp)
                                    .cornerRadius(Spacing.radiusSm)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Spacing.radiusSm)
                                            .stroke(agentCount == count ? Color.accentPurple : Color.borderSubtle, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                // Create Button
                Button {
                    createTicket()
                } label: {
                    Text("Create Ticket")
                        .font(Typography.labelLarge)
                        .foregroundColor(.bgApp)
                        .frame(maxWidth: .infinity)
                        .frame(height: Spacing.buttonHeight)
                        .background(title.isEmpty ? Color.textMuted : Color.accentPurple)
                        .cornerRadius(Spacing.radiusMd)
                }
                .buttonStyle(.plain)
                .disabled(title.isEmpty)
            }
        }
    }

    private func addTag() {
        let trimmed = tagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.contains(trimmed), tags.count < 20 else { return }
        tags.append(trimmed)
        tagInput = ""
    }

    private func createTicket() {
        guard let project = appState.currentProject else { return }
        let ticket = appState.projectService.createTicket(
            title: title,
            ticketDescription: description,
            priority: priority,
            projectId: project.id,
            tags: tags,
            agentCount: agentCount
        )
        appState.tickets.append(ticket)
        isPresented = false
    }
}


// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
