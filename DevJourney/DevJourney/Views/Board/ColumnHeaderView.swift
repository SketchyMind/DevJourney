import SwiftUI

struct ColumnHeaderView: View {
    let stage: Stage
    let ticketCount: Int
    let totalTickets: Int

    private var stageColor: Color {
        Color.clear.colorForStage(stage)
    }

    private var stageIcon: String {
        switch stage {
        case .backlog: return "tray.full"
        case .planning: return "list.bullet.clipboard"
        case .design: return "paintbrush"
        case .dev: return "chevron.left.forwardslash.chevron.right"
        case .debug: return "ant"
        case .complete: return "checkmark.circle"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Stage icon
            Image(systemName: stageIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(stageColor)

            Text(stage.displayName.uppercased())
                .font(.system(size: 12, weight: .bold, design: .default))
                .tracking(1.2)
                .foregroundColor(stageColor == .textMuted ? .textPrimary : stageColor)

            // Count badge (stage-colored when tickets present)
            Text("\(ticketCount)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(ticketCount > 0 ? stageColor : .textSecondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(ticketCount > 0 ? Color.clear.colorForStageDim(stage) : Color.white.opacity(0.06)))
                .overlay(Circle().strokeBorder(ticketCount > 0 ? stageColor.opacity(0.3) : Color.borderSubtle, lineWidth: 1))

            Spacer()
        }
        .padding(.bottom, 10)
    }
}
