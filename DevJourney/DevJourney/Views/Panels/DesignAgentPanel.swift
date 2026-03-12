import SwiftUI

struct TicketDetailPanel: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    let ticket: Ticket

    @State private var showDeleteConfirmation = false
    @State private var showDescription = false
    @State private var showThoughts = false
    @State private var showTimeline = false
    @State private var showClarifications = true
    @State private var showDebug = false
    @State private var reviewerComment = ""

    private var activeSession: AgentSession? {
        appState.activeSessions[ticket.id]
    }

    private var latestSession: AgentSession? {
        ticket.sessions.sorted { $0.startedAt > $1.startedAt }.first
    }

    private var storedSnapshot: StoredTicketSnapshot? {
        guard let project = appState.currentProject else { return nil }
        return try? appState.localTicketStore
            .loadTicketSnapshots(for: project)
            .first(where: { $0.ticket.id == ticket.id })
    }

    private var latestStoredSession: SessionRecord? {
        storedSnapshot?.sessions.max { $0.startedAt < $1.startedAt }
    }

    private var stageColor: Color {
        Color.clear.colorForStage(ticket.stageEnum)
    }

    private var stageColorDim: Color {
        Color.clear.colorForStageDim(ticket.stageEnum)
    }

    private var displayedThoughts: [String] {
        if let session = activeSession, !session.thoughts.isEmpty {
            return session.thoughts
        }
        if let session = latestSession, !session.thoughts.isEmpty {
            return session.thoughts
        }
        return latestStoredSession?.thoughts ?? []
    }

    private var displayedEvents: [AgentExecutionEvent] {
        if let session = activeSession, !session.executionEvents.isEmpty {
            return session.executionEvents.sorted { $0.createdAt < $1.createdAt }
        }
        if let session = latestSession, !session.executionEvents.isEmpty {
            return session.executionEvents.sorted { $0.createdAt < $1.createdAt }
        }
        return latestStoredSession?.executionEvents.sorted { $0.createdAt < $1.createdAt } ?? []
    }

    private var displayedDialog: [DialogEntry] {
        if let session = activeSession, !session.dialog.isEmpty {
            return session.dialog
        }
        if let session = latestSession, !session.dialog.isEmpty {
            return session.dialog
        }
        return latestStoredSession?.dialog ?? []
    }

    private var rawResponse: String? {
        let live = activeSession?.liveResponse.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !live.isEmpty { return live }
        let latest = latestSession?.liveResponse.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !latest.isEmpty { return latest }
        let stored = latestStoredSession?.liveResponse.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return stored.isEmpty ? nil : stored
    }

    private var summaryLines: [String] {
        if !ticket.artifactSummary.isEmpty { return ticket.artifactSummary }
        switch ticket.stageEnum {
        case .planning:
            return storedSnapshot?.planning?.summary ?? []
        case .design:
            return storedSnapshot?.design?.summary ?? []
        case .dev:
            return storedSnapshot?.devExecution?.summary ?? []
        case .debug:
            return storedSnapshot?.debugReport?.summary ?? []
        case .backlog, .complete:
            return []
        }
    }

    private var clarificationItems: [ClarificationItem] {
        ticket.clarifications.sorted { lhs, rhs in
            let leftDate = lhs.answeredAt ?? .distantFuture
            let rightDate = rhs.answeredAt ?? .distantFuture
            return leftDate < rightDate
        }
    }

    private var modelLabel: String {
        activeSession?.modelUsed ?? latestSession?.modelUsed ?? latestStoredSession?.modelUsed ?? ticket.activeModel ?? "Not Configured"
    }

    private var providerLabel: String? {
        activeSession?.providerId ?? latestSession?.providerId ?? latestStoredSession?.providerId ?? ticket.activeProviderConfigId
    }

    private var isReviewable: Bool {
        ticket.handoverStateEnum == .readyForReview || ticket.statusEnum == .done
    }

    private var isRunning: Bool {
        activeSession != nil
            || ticket.handoverStateEnum == .running
            || ticket.statusEnum == .active
    }

    private var displayedStatusLabel: String {
        if isRunning {
            return "Running"
        }
        return ticket.statusEnum.displayName
    }

    private var displayedStatusTint: Color {
        if isRunning {
            return stageColor
        }
        return ticket.statusEnum == .clarify ? .accentRed : .accentBlue
    }

    private var nextStageLabel: String {
        if ticket.stageEnum == .debug {
            return "Complete Ticket"
        }
        return "Pass to \(ticket.stageEnum.nextStage()?.displayName ?? "Next Stage")"
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 0) {
                    panelHeader
                    Rectangle()
                        .fill(Color.borderSubtle)
                        .frame(height: 1)

                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.gapLg) {
                            summaryHeader

                            if !ticket.ticketDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                collapsibleSection(
                                    title: "Description",
                                    subtitle: "Original ticket brief",
                                    isExpanded: $showDescription
                                ) {
                                    Text(ticket.ticketDescription)
                                        .font(Typography.bodyMedium)
                                        .foregroundColor(.textPrimary)
                                        .textSelection(.enabled)
                                }
                            }

                            if !summaryLines.isEmpty {
                                primarySectionCard(
                                    title: "Artifact Summary",
                                    subtitle: "Structured result produced by the agent for this stage."
                                ) {
                                    VStack(alignment: .leading, spacing: Spacing.gapXs) {
                                        ForEach(summaryLines, id: \.self) { line in
                                            HStack(alignment: .top, spacing: Spacing.gapSm) {
                                                Circle()
                                                    .fill(stageColor.opacity(0.85))
                                                    .frame(width: 6, height: 6)
                                                    .padding(.top, 6)
                                                Text(line)
                                                    .font(Typography.bodySmall)
                                                    .foregroundColor(.textPrimary)
                                                    .textSelection(.enabled)
                                            }
                                        }
                                    }
                                }
                            }

                            if !clarificationItems.isEmpty {
                                collapsibleSection(
                                    title: "Clarifications",
                                    subtitle: "\(ticket.pendingClarificationCount) open",
                                    isExpanded: $showClarifications
                                ) {
                                    VStack(alignment: .leading, spacing: Spacing.gapSm) {
                                        ForEach(clarificationItems, id: \.id) { item in
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(item.question)
                                                    .font(Typography.bodySmall)
                                                    .foregroundColor(.textPrimary)
                                                    .textSelection(.enabled)
                                                if let answer = item.answer, !answer.isEmpty {
                                                    Text(answer)
                                                        .font(Typography.captionLarge)
                                                        .foregroundColor(.textSecondary)
                                                        .textSelection(.enabled)
                                                } else {
                                                    Text("Awaiting answer")
                                                        .font(Typography.captionLarge)
                                                        .foregroundColor(.accentYellow)
                                                }
                                            }
                                            .padding(Spacing.sm)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.bgApp)
                                            .cornerRadius(Spacing.radiusSm)
                                        }
                                    }
                                }
                            }

                            if !displayedThoughts.isEmpty {
                                collapsibleSection(
                                    title: "Agent Thoughts",
                                    subtitle: "Secondary execution trace",
                                    isExpanded: $showThoughts
                                ) {
                                    VStack(alignment: .leading, spacing: Spacing.gapSm) {
                                        ForEach(Array(displayedThoughts.enumerated()), id: \.offset) { index, thought in
                                            HStack(alignment: .top, spacing: Spacing.gapSm) {
                                                Image(systemName: "brain")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.accentPurple)
                                                    .padding(.top, 2)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("Thought \(index + 1)")
                                                        .font(Typography.captionSmall)
                                                        .foregroundColor(.textMuted)
                                                    Text(thought)
                                                        .font(Typography.bodySmall)
                                                        .foregroundColor(.textPrimary)
                                                        .textSelection(.enabled)
                                                }
                                            }
                                            .padding(Spacing.sm)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.accentPurpleDim)
                                            .cornerRadius(Spacing.radiusSm)
                                        }
                                    }
                                }
                            }

                            if !displayedEvents.isEmpty {
                                collapsibleSection(
                                    title: "Execution Timeline",
                                    subtitle: "Secondary event log",
                                    isExpanded: $showTimeline
                                ) {
                                    VStack(alignment: .leading, spacing: Spacing.gapSm) {
                                        ForEach(displayedEvents) { event in
                                            HStack(alignment: .top, spacing: Spacing.gapSm) {
                                                Image(systemName: icon(for: event.type))
                                                    .font(.system(size: 12))
                                                    .foregroundColor(color(for: event.type))
                                                    .padding(.top, 2)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    HStack(spacing: Spacing.gapSm) {
                                                        Text(event.type.rawValue)
                                                            .font(Typography.captionSmall)
                                                            .foregroundColor(color(for: event.type))
                                                        Text(event.createdAt.formatted(date: .omitted, time: .standard))
                                                            .font(Typography.captionSmall)
                                                            .foregroundColor(.textMuted)
                                                    }
                                                    Text(event.message)
                                                        .font(Typography.bodySmall)
                                                        .foregroundColor(.textPrimary)
                                                        .textSelection(.enabled)
                                                }
                                            }
                                            .padding(Spacing.sm)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color.bgApp)
                                            .cornerRadius(Spacing.radiusSm)
                                        }
                                    }
                                }
                            }

                            if showDebug {
                                debugSection
                            }
                        }
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, Spacing.lg)
                        .padding(.bottom, 140)
                    }

                    footerActions
                }
                .frame(width: min(max(geometry.size.width * 2 / 3, 560), Spacing.panelMaxWidth))
                .frame(maxHeight: .infinity)
                .padding(.top, Spacing.panelTopMargin)
                .background(Color.bgSurface)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusLg, style: .continuous))
                .overlay(
                    Rectangle()
                        .fill(Color.borderSubtle)
                        .frame(width: 1),
                    alignment: .leading
                )
            }
        }
        .ignoresSafeArea()
        .onAppear {
            showDescription = !isRunning
            showClarifications = ticket.pendingClarificationCount > 0
        }
        .confirmationDialog(
            "Delete this ticket?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Ticket", role: .destructive) {
                appState.deleteTicket(ticket)
                isPresented = false
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the ticket from the board and deletes its local DevJourney ticket folder.")
        }
    }

    private var panelHeader: some View {
        HStack(spacing: Spacing.gapSm) {
            Text("Ticket Details")
                .font(Typography.headingMedium)
                .foregroundColor(.textPrimary)

            GlassEffectContainer(spacing: Spacing.gapSm) {
                HStack(spacing: Spacing.gapSm) {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Delete")
                                .font(Typography.captionSmall)
                        }
                        .foregroundColor(Color(red: 0xFF / 255, green: 0xB4 / 255, blue: 0xB4 / 255))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: Spacing.radiusPill)
                                .fill(Color.accentRed.opacity(0.10))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.radiusPill)
                                .stroke(Color.accentRed.opacity(0.45), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete Ticket")
                }
            }

            Spacer()

            GlassEffectContainer(spacing: Spacing.gapSm) {
                HStack(spacing: Spacing.gapSm) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showDebug.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "ladybug")
                                .font(.system(size: 11, weight: .semibold))
                            Text(showDebug ? "Debug On" : "Debug")
                                .font(Typography.captionSmall)
                        }
                        .foregroundColor(showDebug ? .accentYellow : .textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassEffect(
                            showDebug
                                ? .regular.tint(.accentYellow).interactive()
                                : .regular.interactive(),
                            in: .rect(cornerRadius: Spacing.radiusPill)
                        )
                    }
                    .buttonStyle(.plain)

                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.textSecondary)
                            .frame(width: 28, height: 28)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.gapSm) {
            Text(ticket.title)
                .font(Typography.headingSmall)
                .foregroundColor(.textPrimary)

            HStack(spacing: Spacing.gapSm) {
                headerPill(ticket.stageEnum.displayName, tint: stageColor)
                headerPill(displayedStatusLabel, tint: displayedStatusTint)
                headerPill(ticket.handoverStateEnum.displayName, tint: .textSecondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Provider: \(providerLabel ?? "Not Configured")")
                    .font(Typography.captionLarge)
                    .foregroundColor(.textSecondary)
                Text("Model: \(modelLabel)")
                    .font(Typography.captionLarge)
                    .foregroundColor(.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var debugSection: some View {
        primarySectionCard(
            title: "Debug Details",
            subtitle: "Prompt assembly and raw model output."
        ) {
            VStack(alignment: .leading, spacing: Spacing.gapLg) {
                if !displayedDialog.isEmpty {
                    debugBlock("Conversation") {
                        VStack(alignment: .leading, spacing: Spacing.gapSm) {
                            ForEach(Array(displayedDialog.enumerated()), id: \.offset) { _, entry in
                                HStack(alignment: .top, spacing: Spacing.gapSm) {
                                    Image(systemName: entry.role == "user" ? "person.fill" : "cpu")
                                        .font(.system(size: 12))
                                        .foregroundColor(entry.role == "user" ? .accentBlue : .agentMechanic)
                                        .padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.role == "user" ? "Compiled Prompt" : "Agent")
                                            .font(Typography.captionSmall)
                                            .foregroundColor(entry.role == "user" ? .accentBlue : .agentMechanic)
                                        Text(entry.content)
                                            .font(Typography.bodySmall)
                                            .foregroundColor(.textPrimary)
                                            .textSelection(.enabled)
                                    }
                                }
                                .padding(Spacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(entry.role == "user" ? Color.accentBlueDim : Color.agentMechanicDim)
                                .cornerRadius(Spacing.radiusSm)
                            }
                        }
                    }
                }

                if let rawResponse, !rawResponse.isEmpty {
                    debugBlock("Raw Agent Output") {
                        Text(rawResponse)
                            .font(Typography.bodySmall)
                            .foregroundColor(.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var footerActions: some View {
        VStack(spacing: Spacing.gapMd) {
            Rectangle()
                .fill(Color.borderSubtle)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: Spacing.gapSm) {
                Text(isReviewable ? "Review Comment" : "Agent Comment")
                    .font(Typography.labelMedium)
                    .foregroundColor(.textSecondary)

                TextEditor(text: $reviewerComment)
                    .font(Typography.bodySmall)
                    .foregroundColor(.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(height: 84)
                    .padding(Spacing.sm)
                    .background(Color.bgApp)
                    .cornerRadius(Spacing.radiusSm)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.radiusSm)
                            .stroke(Color.borderSubtle, lineWidth: 1)
                    )
            }

            GlassEffectContainer(spacing: Spacing.gapSm) {
                Group {
                    if isRunning {
                        HStack(spacing: Spacing.gapSm) {
                            footerPillButton(
                                "Stop Agent",
                                icon: "stop.fill",
                                backgroundColor: Color.white.opacity(0.05),
                                borderColor: Color.white.opacity(0.15),
                                textColor: .accentRed,
                                fillsWidth: false
                            ) {
                                appState.stopStage(for: ticket)
                            }

                            Spacer(minLength: 0)
                        }
                    } else if isReviewable {
                        HStack(spacing: Spacing.gapSm) {
                            footerPillButton(
                                "Run again",
                                icon: "arrow.clockwise",
                                backgroundColor: Color.accentOrangeDim,
                                borderColor: .accentOrange,
                                textColor: Color(red: 0xFD / 255, green: 0xD5 / 255, blue: 0xB4 / 255)
                            ) {
                                requestChanges()
                            }

                            footerPillButton(
                                nextStageLabel,
                                icon: "checkmark",
                                backgroundColor: Color.accentGreenDim,
                                borderColor: .accentGreen,
                                textColor: Color(red: 0x86 / 255, green: 0xEF / 255, blue: 0xAC / 255)
                            ) {
                                approveReview()
                            }
                        }
                    } else {
                        HStack(spacing: Spacing.gapSm) {
                            footerPillButton(
                                "Run again",
                                icon: "arrow.clockwise",
                                backgroundColor: stageColorDim,
                                borderColor: stageColor,
                                textColor: stageColor
                            ) {
                                sendAgainToAgent()
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.xl)
        .background(Color.bgSurface)
    }

    private func collapsibleSection<Content: View>(
        title: String,
        subtitle: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.gapSm) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: Spacing.gapSm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Typography.labelMedium)
                            .foregroundColor(.textPrimary)
                        Text(subtitle)
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                    }
                    Spacer()
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textMuted)
                }
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgElevated)
        .cornerRadius(Spacing.radiusMd)
    }

    private func primarySectionCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.gapSm) {
            Text(title)
                .font(Typography.labelMedium)
                .foregroundColor(.textPrimary)
            Text(subtitle)
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)
            content()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgElevated)
        .cornerRadius(Spacing.radiusMd)
    }

    private func debugBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.gapSm) {
            Text(title)
                .font(Typography.labelMedium)
                .foregroundColor(.textSecondary)
            content()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgApp)
        .cornerRadius(Spacing.radiusSm)
    }

    private func headerPill(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(Typography.captionSmall)
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.04))
            .cornerRadius(Spacing.radiusPill)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusPill)
                    .stroke(Color.borderSubtle, lineWidth: 1)
            )
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: Spacing.gapSm) {
            Image(systemName: icon)
            Text(title)
        }
        .font(Typography.labelLarge)
        .frame(maxWidth: .infinity)
        .frame(height: Spacing.buttonHeight)
    }

    private func footerPillButton(
        _ title: String,
        icon: String,
        backgroundColor: Color,
        borderColor: Color,
        textColor: Color,
        fillsWidth: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(textColor)
            .padding(.horizontal, 14)
            .frame(maxWidth: fillsWidth ? .infinity : nil)
            .frame(height: 34)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusPill)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusPill))
        }
        .buttonStyle(.plain)
    }

    private func requestChanges() {
        let trimmedComment = reviewerComment.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = appState.workflowService.submitReviewDecision(
            for: ticket,
            approved: false,
            comment: trimmedComment
        )
        reviewerComment = ""
        appState.resumeStage(for: ticket)
        isPresented = false
    }

    private func approveReview() {
        let trimmedComment = reviewerComment.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = appState.workflowService.submitReviewDecision(
            for: ticket,
            approved: true,
            comment: trimmedComment
        )
        reviewerComment = ""
        isPresented = false
    }

    private func sendAgainToAgent() {
        let trimmedComment = reviewerComment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedComment.isEmpty {
            appState.workflowService.addOperatorInstruction(trimmedComment, for: ticket)
        }
        reviewerComment = ""
        appState.resumeStage(for: ticket)
    }

    private func icon(for type: AgentExecutionEventType) -> String {
        switch type {
        case .started:
            return "play.fill"
        case .tokenDelta:
            return "text.cursor"
        case .thoughtDelta:
            return "brain"
        case .toolCall:
            return "wrench.and.screwdriver.fill"
        case .artifactPatched:
            return "square.and.pencil"
        case .clarificationRequested:
            return "questionmark.circle.fill"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    private func color(for type: AgentExecutionEventType) -> Color {
        switch type {
        case .started:
            return .accentGreen
        case .tokenDelta:
            return .accentBlue
        case .thoughtDelta:
            return .accentPurple
        case .toolCall:
            return .accentYellow
        case .artifactPatched:
            return .agentMechanic
        case .clarificationRequested:
            return .accentYellow
        case .completed:
            return .accentGreen
        case .failed:
            return .accentRed
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isPresented = false
        }
    }
}
