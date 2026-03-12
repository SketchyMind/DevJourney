import SwiftUI

struct TicketCardView: View {
    @EnvironmentObject var appState: AppState
    let ticket: Ticket
    var onOpenDetails: () -> Void = {}
    var onStartTicket: () -> Void = {}
    var onStartStage: () -> Void = {}
    var onStopStage: () -> Void = {}
    var onClarify: () -> Void = {}
    var onReview: () -> Void = {}
    var onComplete: () -> Void = {}
    var onShowHistory: () -> Void = {}

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stage: Stage { ticket.stageEnum }
    private var status: TicketStatus { ticket.statusEnum }
    private var stageColor: Color { Color.clear.colorForStage(stage) }
    private var stageColorDim: Color { Color.clear.colorForStageDim(stage) }

    private var modelDisplayName: String {
        if let session = appState.activeSessions[ticket.id] {
            return session.modelUsed
        }
        return ticket.activeModel ?? "Not Configured"
    }

    private var providerDisplayName: String {
        if let session = appState.activeSessions[ticket.id],
           let providerId = session.providerId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !providerId.isEmpty {
            return providerId
        }

        guard let configId = ticket.activeProviderConfigId,
              !configId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "No Provider"
        }

        if let config = appState.currentProject?.providerConfigs.first(where: { $0.id == configId }) {
            return config.displayName
        }

        return configId
    }

    private var scoreText: String {
        "\(Int(ticket.stageScore.rounded()))%"
    }

    private var summaryPreview: [String] {
        Array(ticket.artifactSummary.prefix(2))
    }

    private var blockedReasonPreview: String? {
        let trimmed = ticket.blockedReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var hasOpenClarifications: Bool {
        ticket.pendingClarificationCount > 0
    }

    private var isRunning: Bool {
        appState.activeSessions[ticket.id] != nil
            || ticket.handoverStateEnum == .running
            || status == .active
    }

    private var effectiveStatus: TicketStatus {
        isRunning ? .active : status
    }

    @ViewBuilder
    private var celebrateBar: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                .accentGreen,
                .accentPurple.opacity(0.7),
                .accentGreen
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                // Celebrate bar (complete state only)
                if status == .complete {
                    celebrateBar
                        .frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusMd))
                        .padding(.horizontal, -16)
                        .padding(.top, -16)
                }

                Button(action: onOpenDetails) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ticket.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textPrimary)
                            .lineLimit(2)

                        if ticket.priorityEnum == .high {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.accentRed)
                                    .frame(width: 6, height: 6)
                                Text("High Priority")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.accentRed)
                            }
                        }

                        HStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "cpu")
                                    .font(.system(size: 10, weight: .regular))
                                Text(modelDisplayName)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .regular))
                            }
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 100).fill(Color.white.opacity(0.03)))
                            .overlay(RoundedRectangle(cornerRadius: 100).strokeBorder(Color.borderSubtle, lineWidth: 1))

                            HStack(spacing: 4) {
                                Image(systemName: "network")
                                    .font(.system(size: 10, weight: .regular))
                                Text(providerDisplayName)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .regular))
                            }
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 100).fill(Color.white.opacity(0.03)))
                            .overlay(RoundedRectangle(cornerRadius: 100).strokeBorder(Color.borderSubtle, lineWidth: 1))

                            Spacer()
                        }

                        HStack(spacing: 8) {
                            metaBadge(title: "Score", value: scoreText, tint: stageColor)
                            metaBadge(title: "Gate", value: ticket.handoverStateEnum.displayName, tint: .accentBlue)
                            if ticket.pendingClarificationCount > 0 {
                                metaBadge(
                                    title: "Q",
                                    value: "\(ticket.pendingClarificationCount)",
                                    tint: .accentYellow
                                )
                            }
                        }

                        if !summaryPreview.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(summaryPreview, id: \.self) { line in
                                    HStack(alignment: .top, spacing: 6) {
                                        Circle()
                                            .fill(stageColor.opacity(0.8))
                                            .frame(width: 4, height: 4)
                                            .padding(.top, 5)
                                        Text(line)
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundColor(.textSecondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }

                        if status == .clarify, let blockedReasonPreview {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.accentRed)
                                    .padding(.top, 2)
                                Text(blockedReasonPreview)
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(.textSecondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(RoundedRectangle(cornerRadius: Spacing.radiusMd))
                }
                .buttonStyle(.plain)

                // Card Bottom (Status + Button)
                HStack(spacing: 0) {
                    statusText
                    Spacer()
                    actionButton
                }
            }
            .padding(16)
            .background(
                cardBackground
                    .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusMd))
            )
            .overlay(cardBorder)
            .frame(maxWidth: .infinity)
            .modifier(ActivePulseModifier(
                isActive: isRunning,
                isHovered: isHovered,
                stageColor: stageColor,
                reduceMotion: reduceMotion
            ))
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }

            // Complete checkmark badge
            if status == .complete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(.accentGreen)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: status)
        .contextMenu {
            Button("View History") { onShowHistory() }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch effectiveStatus {
        case .inactive:
            Text("Inactive")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.textSecondary)

        case .ready:
            Text("Ready")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.textSecondary)

        case .active:
            HStack(spacing: 6) {
                PulsingDot(color: stageColor)
                Text("Running")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(stageColor)
            }

        case .clarify:
            HStack(spacing: 6) {
                PulsingDot(color: .accentRed)
                Text(blockedReasonPreview ?? "Open questions")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.accentRed)
                    .lineLimit(1)
            }

        case .done:
            Text("Done")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.accentGreen)

        case .complete:
            Text("Complete")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.accentGreen)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch effectiveStatus {
        case .inactive:
            stageButton(
                icon: "paperplane.fill",
                title: "Start Ticket",
                backgroundColor: Color.white.opacity(0.05),
                borderColor: Color.white.opacity(0.15),
                textColor: .textPrimary,
                action: onStartTicket
            )

        case .ready:
            switch stage {
            case .backlog:
                stageButton(
                    icon: "paperplane.fill",
                    title: "Start Ticket",
                    backgroundColor: Color.white.opacity(0.05),
                    borderColor: Color.white.opacity(0.15),
                    textColor: stageColor,
                    action: onStartStage
                )
            case .planning:
                stageButton(
                    icon: "list.bullet.clipboard",
                    title: "Start Planning",
                    backgroundColor: stageColorDim,
                    borderColor: stageColor,
                    textColor: Color(red: 0xDD / 255, green: 0xCD / 255, blue: 0xFE / 255),
                    action: onStartStage
                )
            case .design:
                stageButton(
                    icon: "paintbrush.fill",
                    title: "Start Design",
                    backgroundColor: stageColorDim,
                    borderColor: stageColor,
                    textColor: Color(red: 0xB6 / 255, green: 0xD5 / 255, blue: 0xFB / 255),
                    action: onStartStage
                )
            case .dev:
                stageButton(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "Start Dev",
                    backgroundColor: stageColorDim,
                    borderColor: stageColor,
                    textColor: Color(red: 0xFC / 255, green: 0xE1 / 255, blue: 0x9C / 255),
                    action: onStartStage
                )
            case .debug:
                stageButton(
                    icon: "ant.fill",
                    title: "Start Debug",
                    backgroundColor: stageColorDim,
                    borderColor: stageColor,
                    textColor: Color(red: 0xFD / 255, green: 0xD5 / 255, blue: 0xB4 / 255),
                    action: onStartStage
                )
            case .complete:
                EmptyView()
            }

        case .active:
            stageButton(
                icon: "stop.circle.fill",
                title: "Stop",
                backgroundColor: Color.white.opacity(0.05),
                borderColor: Color.white.opacity(0.15),
                textColor: .accentRed,
                action: onStopStage
            )

        case .clarify:
            stageButton(
                icon: hasOpenClarifications ? "bubble.left.and.text.bubble.right.fill" : "arrow.clockwise",
                title: hasOpenClarifications ? "Clarify" : "Retry",
                backgroundColor: stageColorDim,
                borderColor: stageColor,
                textColor: stageColor,
                action: hasOpenClarifications ? onClarify : onStartStage
            )

        case .done:
            stageButton(
                icon: "checkmark.shield.fill",
                title: "Review",
                backgroundColor: Color.accentGreenDim,
                borderColor: .accentGreen,
                textColor: Color(red: 0x86 / 255, green: 0xEF / 255, blue: 0xAC / 255),
                action: onReview
            )

        case .complete:
            EmptyView()
        }
    }

    private func metaBadge(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.textMuted)
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.03))
        .cornerRadius(Spacing.radiusPill)
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.radiusPill)
                .stroke(Color.borderSubtle, lineWidth: 1)
        )
    }

    private func stageButton(
        icon: String,
        title: String,
        backgroundColor: Color,
        borderColor: Color,
        textColor: Color,
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
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(backgroundColor)
            .overlay(RoundedRectangle(cornerRadius: 100).strokeBorder(borderColor, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 100))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isRunning {
            RunningTicketSurface(
                stageColor: stageColor,
                stageColorDim: stageColorDim,
                reduceMotion: reduceMotion
            )
        } else {
            RoundedRectangle(cornerRadius: Spacing.radiusMd)
                .fill(Color.white.opacity(0.05))
        }
    }

    @ViewBuilder
    private var cardBorder: some View {
        if status == .clarify {
            RoundedRectangle(cornerRadius: Spacing.radiusMd)
                .strokeBorder(Color.accentRed, lineWidth: 1)
        } else if status == .complete {
            RoundedRectangle(cornerRadius: Spacing.radiusMd)
                .strokeBorder(Color.accentGreen, lineWidth: 1.5)
        } else if isRunning {
            RunningTicketBorder(
                stageColor: stageColor,
                stageColorDim: stageColorDim,
                reduceMotion: reduceMotion
            )
        } else {
            RoundedRectangle(cornerRadius: Spacing.radiusMd)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        }
    }
}

// MARK: - Active Card Pulse Modifier

struct ActivePulseModifier: ViewModifier {
    let isActive: Bool
    let isHovered: Bool
    let stageColor: Color
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if isActive && !reduceMotion {
            content
                .shadow(
                    color: stageColor.opacity(0.26),
                    radius: 18,
                    x: 0,
                    y: 6
                )
        } else if isActive && reduceMotion {
            content
                .shadow(color: stageColor.opacity(0.24), radius: 18, x: 0, y: 6)
        } else {
            content
                .brightness(isHovered ? 0.03 : 0.0)
                .shadow(
                    color: isHovered ? Color.black.opacity(0.3) : Color.black.opacity(0.15),
                    radius: isHovered ? 8 : 4,
                    x: 0,
                    y: isHovered ? 4 : 2
                )
        }
    }
}

private struct RunningTicketSurface: View {
    let stageColor: Color
    let stageColorDim: Color
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            if #available(macOS 26.0, iOS 26.0, *) {
                RoundedRectangle(cornerRadius: Spacing.radiusMd)
                    .fill(Color.white.opacity(0.001))
                    .glassEffect(
                        .regular.tint(stageColor.opacity(0.18)),
                        in: .rect(cornerRadius: Spacing.radiusMd)
                    )
                    .opacity(0.55)
            }

            background()
        }
    }

    private func background() -> some View {
        RoundedRectangle(cornerRadius: Spacing.radiusMd)
            .fill(Color.bgCard.opacity(0.94))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusMd)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.05),
                                Color.white.opacity(0.015),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusMd)
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.04),
                                Color.clear
                            ]),
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 160
                        )
                    )
                    .blendMode(.plusLighter)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusMd)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct RunningTicketBorder: View {
    let stageColor: Color
    let stageColorDim: Color
    let reduceMotion: Bool

    private var geminiGradient: Gradient {
        Gradient(stops: [
            .init(color: Color(red: 0x00 / 255, green: 0x8A / 255, blue: 0xFC / 255), location: 0.00),
            .init(color: Color(red: 0x00 / 255, green: 0x8A / 255, blue: 0xFC / 255), location: 0.27),
            .init(color: Color(red: 0xFC / 255, green: 0x4F / 255, blue: 0x4C / 255), location: 0.33),
            .init(color: Color(red: 0xFF / 255, green: 0xDA / 255, blue: 0x00 / 255), location: 0.41),
            .init(color: Color(red: 0x00 / 255, green: 0xE4 / 255, blue: 0x5A / 255), location: 0.49),
            .init(color: Color(red: 0x00 / 255, green: 0x8A / 255, blue: 0xFC / 255), location: 0.65),
            .init(color: Color(red: 0x00 / 255, green: 0xC7 / 255, blue: 0x59 / 255), location: 0.93),
            .init(color: Color(red: 0x00 / 255, green: 0x8A / 255, blue: 0xFC / 255), location: 1.00)
        ])
    }

    var body: some View {
        if reduceMotion {
            border(rotation: 28)
        } else {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                border(rotation: t * 58)
            }
        }
    }

    private func border(rotation: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Spacing.radiusMd)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)

            RoundedRectangle(cornerRadius: Spacing.radiusMd)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.03),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            gradientLayer(rotation: rotation)
                .mask(
                    RoundedRectangle(cornerRadius: Spacing.radiusMd)
                        .stroke(lineWidth: 2.2)
                )

            gradientLayer(rotation: rotation)
                .mask(
                    RoundedRectangle(cornerRadius: Spacing.radiusMd)
                        .stroke(lineWidth: 5.4)
                )
                .blur(radius: 12)
                .opacity(0.58)
        }
        .padding(-2)
    }

    private func gradientLayer(rotation: Double) -> some View {
        Rectangle()
            .fill(
                AngularGradient(
                    gradient: geminiGradient,
                    center: UnitPoint(x: 0.52, y: 0.49),
                    startAngle: .degrees(rotation),
                    endAngle: .degrees(rotation + 360)
                )
            )
            .blendMode(.screen)
    }
}

// MARK: - Pulsing Dot Animation

struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 12, height: 12)
                .scaleEffect(isPulsing ? 1.4 : 1.0)
                .opacity(isPulsing ? 0 : 0.6)

            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}
