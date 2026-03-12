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

    private var storedSnapshot: StoredTicketSnapshot? {
        guard let project = appState.currentProject else { return nil }
        return try? appState.localTicketStore
            .loadTicketSnapshots(for: project)
            .first(where: { $0.ticket.id == ticket.id })
    }

    private var latestStoredSession: SessionRecord? {
        storedSnapshot?.sessions.max { $0.startedAt < $1.startedAt }
    }

    private var latestSessionDurationSeconds: Int? {
        if let duration = latestSession?.durationSeconds {
            return duration
        }
        guard let session = latestStoredSession else { return nil }
        let end = session.endedAt ?? Date()
        return Int(end.timeIntervalSince(session.startedAt))
    }

    private var summaryLines: [String] {
        if let session = latestSession, !session.resultSummary.isEmpty {
            return session.resultSummary
        }
        if !ticket.artifactSummary.isEmpty {
            return ticket.artifactSummary
        }
        if let storedSummary = storedArtifactSummary, !storedSummary.isEmpty {
            return storedSummary
        }
        if let session = latestStoredSession, !session.resultSummary.isEmpty {
            return session.resultSummary
        }
        if let response = rawResponse {
            return response
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }

    private var rawResponse: String? {
        let trimmed = latestSession?.liveResponse.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty == false {
            return trimmed
        }
        let storedTrimmed = latestStoredSession?.liveResponse.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return storedTrimmed.isEmpty ? nil : storedTrimmed
    }

    private var storedArtifactSummary: [String]? {
        guard let snapshot = storedSnapshot else { return nil }
        switch ticket.stageEnum {
        case .planning:
            return snapshot.planning?.summary
        case .design:
            return snapshot.design?.summary
        case .dev:
            return snapshot.devExecution?.summary
        case .debug:
            return snapshot.debugReport?.summary
        case .backlog, .complete:
            return nil
        }
    }

    private var artifactSections: [(title: String, lines: [String])] {
        switch ticket.stageEnum {
        case .planning:
            if let spec = ticket.latestPlanningSpec {
                return [
                    section("Problem", spec.problem),
                    section("Scope In", spec.scopeIn),
                    section("Scope Out", spec.scopeOut),
                    section("Acceptance Criteria", spec.acceptanceCriteria),
                    section("Dependencies", spec.dependencies),
                    section("Assumptions", spec.assumptions),
                    section("Risks", spec.risks),
                    section("Subtasks", spec.subtasks),
                    section("Definition of Ready", spec.definitionOfReady)
                ].filter { !$0.lines.isEmpty }
            }
            guard let spec = storedSnapshot?.planning else { return [] }
            return [
                section("Problem", spec.problem),
                section("Scope In", spec.scopeIn),
                section("Scope Out", spec.scopeOut),
                section("Acceptance Criteria", spec.acceptanceCriteria),
                section("Dependencies", spec.dependencies),
                section("Assumptions", spec.assumptions),
                section("Risks", spec.risks),
                section("Subtasks", spec.subtasks),
                section("Definition of Ready", spec.definitionOfReady)
            ].filter { !$0.lines.isEmpty }

        case .design:
            if let spec = ticket.latestDesignSpec {
                return [
                    section("App Placement", spec.appPlacement),
                    section("Affected Screens", spec.affectedScreens),
                    section("User Flow", spec.userFlow),
                    section("Components", spec.components),
                    section("States", spec.statesMatrix),
                    section("Responsive Rules", spec.responsiveRules),
                    section("Accessibility Notes", spec.accessibilityNotes),
                    section("Figma References", spec.figmaRefs)
                ].filter { !$0.lines.isEmpty }
            }
            guard let spec = storedSnapshot?.design else { return [] }
            return [
                section("App Placement", spec.appPlacement),
                section("Affected Screens", spec.affectedScreens),
                section("User Flow", spec.userFlow),
                section("Components", spec.components),
                section("States", spec.statesMatrix),
                section("Responsive Rules", spec.responsiveRules),
                section("Accessibility Notes", spec.accessibilityNotes),
                section("Figma References", spec.figmaRefs)
            ].filter { !$0.lines.isEmpty }

        case .dev:
            if let execution = ticket.latestDevExecution {
                return [
                    section("Branch", execution.branch),
                    section("Implementation Notes", execution.implementationNotes),
                    section("Changed Files", execution.changedFiles.map { "\($0.path) (\($0.status))" }),
                    section("Preview URLs", execution.previewURLs),
                    section("Commits", execution.commitList),
                    section("Build Status", execution.buildStatus)
                ].filter { !$0.lines.isEmpty }
            }
            guard let execution = storedSnapshot?.devExecution else { return [] }
            return [
                section("Branch", execution.branch),
                section("Implementation Notes", execution.implementationNotes),
                section("Changed Files", execution.changedFiles.map { "\($0.path) (\($0.status))" }),
                section("Preview URLs", execution.previewURLs),
                section("Commits", execution.commitList),
                section("Build Status", execution.buildStatus)
            ].filter { !$0.lines.isEmpty }

        case .debug:
            if let report = ticket.latestDebugReport {
                return [
                    section("Tested Scenarios", report.testedScenarios),
                    section("Failed Scenarios", report.failedScenarios),
                    section("Bug Items", report.bugItems),
                    section("Severity Summary", report.severitySummary),
                    section("Release Recommendation", report.releaseRecommendation)
                ].filter { !$0.lines.isEmpty }
            }
            guard let report = storedSnapshot?.debugReport else { return [] }
            return [
                section("Tested Scenarios", report.testedScenarios),
                section("Failed Scenarios", report.failedScenarios),
                section("Bug Items", report.bugItems),
                section("Severity Summary", report.severitySummary),
                section("Release Recommendation", report.releaseRecommendation)
            ].filter { !$0.lines.isEmpty }

        case .backlog, .complete:
            return []
        }
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
                        if let durationSeconds = latestSessionDurationSeconds {
                            Text("--")
                                .foregroundColor(.textMuted)
                            Text("\(durationSeconds)s")
                                .font(Typography.captionLarge)
                                .foregroundColor(.textMuted)
                        }
                    }
                }

                Divider().background(Color.borderSubtle)

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.gapLg) {
                        // Result summary
                        if !summaryLines.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.gapSm) {
                                Text("Summary")
                                    .font(Typography.labelMedium)
                                    .foregroundColor(.textSecondary)
                                ForEach(summaryLines, id: \.self) { point in
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

                        if !artifactSections.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.gapLg) {
                                Text("Artifact")
                                    .font(Typography.labelMedium)
                                    .foregroundColor(.textSecondary)
                                ForEach(Array(artifactSections.enumerated()), id: \.offset) { _, section in
                                    VStack(alignment: .leading, spacing: Spacing.gapXs) {
                                        Text(section.title)
                                            .font(Typography.labelMedium)
                                            .foregroundColor(.textPrimary)
                                        ForEach(section.lines, id: \.self) { line in
                                            HStack(alignment: .top, spacing: Spacing.gapSm) {
                                                Circle()
                                                    .fill(Color.borderSubtle)
                                                    .frame(width: 5, height: 5)
                                                    .padding(.top, 6)
                                                Text(line)
                                                    .font(Typography.bodySmall)
                                                    .foregroundColor(.textSecondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Files changed
                        let filesChanged = latestSession?.filesChanged ?? latestStoredSession?.filesChanged ?? []
                        if !filesChanged.isEmpty {
                            VStack(alignment: .leading, spacing: Spacing.gapSm) {
                                Text("Files Changed (\(filesChanged.count))")
                                    .font(Typography.labelMedium)
                                    .foregroundColor(.textSecondary)
                                ForEach(filesChanged, id: \.path) { file in
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
                        let commitCount = latestSession?.commitCount ?? latestStoredSession?.commitCount ?? 0
                        if commitCount > 0 {
                            HStack(spacing: Spacing.gapSm) {
                                Image(systemName: "arrow.triangle.branch")
                                    .foregroundColor(.textMuted)
                                Text("\(commitCount) commit\(commitCount == 1 ? "" : "s")")
                                    .font(Typography.bodySmall)
                                    .foregroundColor(.textSecondary)
                            }
                        }

                        if let rawResponse {
                            VStack(alignment: .leading, spacing: Spacing.gapSm) {
                                Text("Agent Response")
                                    .font(Typography.labelMedium)
                                    .foregroundColor(.textSecondary)
                                ScrollView {
                                    Text(rawResponse)
                                        .textSelection(.enabled)
                                        .font(Typography.bodySmall)
                                        .foregroundColor(.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(Spacing.sm)
                                }
                                .frame(minHeight: 120)
                                .background(Color.bgApp)
                                .cornerRadius(Spacing.radiusSm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Spacing.radiusSm)
                                        .stroke(Color.borderSubtle, lineWidth: 1)
                                )
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
        _ = nextStage
        _ = appState.workflowService.submitReviewDecision(
            for: ticket,
            approved: true,
            comment: reviewerComment
        )
        isPresented = false
    }

    private func requestChanges() {
        _ = appState.workflowService.submitReviewDecision(
            for: ticket,
            approved: false,
            comment: reviewerComment
        )
        reviewerComment = ""
        appState.resumeStage(for: ticket)
        isPresented = false
    }

    private func section(_ title: String, _ line: String) -> (title: String, lines: [String]) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, trimmed.isEmpty ? [] : [trimmed])
    }

    private func section(_ title: String, _ lines: [String]) -> (title: String, lines: [String]) {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return (title, cleaned)
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
