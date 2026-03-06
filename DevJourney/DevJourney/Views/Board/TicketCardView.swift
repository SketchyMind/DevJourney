import SwiftUI

struct TicketCardView: View {
    @EnvironmentObject var appState: AppState
    let ticket: Ticket
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
        let model = ticket.aiModel
        if model.contains("opus") { return "Opus 4.6" }
        if model.contains("sonnet") { return "Sonnet 4.5" }
        if model.contains("haiku") { return "Haiku 4.5" }
        return model
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

                // Card Title
                Text(ticket.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textPrimary)
                    .lineLimit(2)

                // Priority indicator for high priority
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

                // AI Config (ModelPill + AgentPill)
                HStack(spacing: 6) {
                    // Model Pill
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

                    // Agent Pill
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10, weight: .regular))
                        Text("Agents \u{00D7}\(ticket.agentCount)")
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

                // Card Bottom (Status + Button)
                HStack(spacing: 0) {
                    statusText
                    Spacer()
                    actionButton
                }
            }
            .padding(16)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusMd))
            .frame(maxWidth: .infinity)
            // Active card glow + pulse via TimelineView
            .modifier(ActivePulseModifier(
                isActive: status == .active,
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
        switch status {
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
                Text("Active")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(stageColor)
            }

        case .clarify:
            HStack(spacing: 6) {
                PulsingDot(color: .accentRed)
                Text("Open questions")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.accentRed)
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
        switch status {
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
                icon: "bubble.left.and.text.bubble.right.fill",
                title: "Clarify",
                backgroundColor: stageColorDim,
                borderColor: stageColor,
                textColor: stageColor,
                action: onClarify
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
        if status == .active {
            RoundedRectangle(cornerRadius: Spacing.radiusMd)
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [stageColorDim.opacity(0.65), Color.bgCard.opacity(0)]),
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 150
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radiusMd)
                        .fill(Color.bgCard.opacity(0.8))
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
        } else if status == .active {
            RoundedRectangle(cornerRadius: Spacing.radiusMd)
                .strokeBorder(stageColor.opacity(0.4), lineWidth: 2)
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
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = (sin(t * (2 * .pi / 0.8)) * 0.5 + 0.5)

                content
                    .scaleEffect(1.0 + 0.015 * phase)
                    .shadow(
                        color: stageColor.opacity(0.4 + 0.1 * phase),
                        radius: 12 + 4 * phase,
                        x: 0, y: 0
                    )
            }
        } else if isActive && reduceMotion {
            content
                .scaleEffect(1.0)
                .shadow(color: stageColor.opacity(0.5), radius: 16, x: 0, y: 0)
        } else {
            content
                .scaleEffect(isHovered ? 1.01 : 1.0)
                .shadow(
                    color: isHovered ? Color.black.opacity(0.3) : Color.black.opacity(0.15),
                    radius: isHovered ? 8 : 4,
                    x: 0,
                    y: isHovered ? 4 : 2
                )
        }
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
