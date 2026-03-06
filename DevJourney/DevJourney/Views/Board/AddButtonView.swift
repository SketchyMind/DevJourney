import SwiftUI

struct AddButtonView: View {
    let stage: Stage
    var onAdd: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                Text("New Ticket")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Spacing.radiusMd)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentPurple,
                                Color.accentPurple.opacity(0.8)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusMd)
                    .strokeBorder(Color.accentPurple.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: Color.accentPurple.opacity(isHovered ? 0.4 : 0.2), radius: isHovered ? 8 : 4, x: 0, y: 2)
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
