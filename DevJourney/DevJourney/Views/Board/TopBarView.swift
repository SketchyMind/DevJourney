import SwiftUI

struct TopBarView: View {
    @EnvironmentObject var appState: AppState
    var onSettingsTapped: () -> Void = {}

    @State private var searchHovered = false
    @State private var bellHovered = false
    @State private var avatarHovered = false
    @State private var gearHovered = false

    var body: some View {
        HStack(spacing: Spacing.lg) {
            // Left: Logo + App name
            HStack(spacing: 8) {
                // Logo icon with gradient
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.accentPurple, Color(red: 0xF4 / 255, green: 0x72 / 255, blue: 0xB6 / 255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 24, height: 24)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }

                Text("DevJourney")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
            }

            // Project name pill
            Button(action: onSettingsTapped) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.accentPurple)
                    Text(appState.currentProject?.name ?? "Project")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.textMuted)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Spacing.radiusMd).fill(Color.bgElevated))
            }
            .buttonStyle(.plain)

            // Branch pill (always visible)
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .regular))
                Text(appState.currentBranch)
                    .font(Typography.pillTextMono)
                Circle()
                    .fill(appState.currentProject?.githubRepo != nil ? Color.accentGreen : Color.textMuted)
                    .frame(width: 6, height: 6)
            }
            .foregroundColor(.textSecondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Spacing.radiusMd).fill(Color.bgElevated))
            .accessibilityLabel("Branch \(appState.currentBranch)")

            Spacer()

            // Right: Gear + Search + Bell + Avatar
            HStack(spacing: Spacing.gapLg) {
                Button(action: onSettingsTapped) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(gearHovered ? .textPrimary : .textSecondary)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: Spacing.radiusSm).fill(gearHovered ? Color.white.opacity(0.05) : Color.clear))
                        .animation(.hoverFast, value: gearHovered)
                }
                .buttonStyle(.plain)
                .onHover { gearHovered = $0 }
                .accessibilityLabel("Project Settings")

                Button(action: {}) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(searchHovered ? .textPrimary : .textSecondary)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: Spacing.radiusSm).fill(searchHovered ? Color.white.opacity(0.05) : Color.clear))
                        .animation(.easeOut(duration: 0.15), value: searchHovered)
                }
                .buttonStyle(.plain)
                .onHover { searchHovered = $0 }

                Button(action: {}) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(bellHovered ? .textPrimary : .textSecondary)
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: Spacing.radiusSm).fill(bellHovered ? Color.white.opacity(0.05) : Color.clear))
                            .animation(.easeOut(duration: 0.15), value: bellHovered)
                    }
                }
                .buttonStyle(.plain)
                .onHover { bellHovered = $0 }

                // Profile avatar
                Button(action: {}) {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0xF4 / 255, green: 0x72 / 255, blue: 0xB6 / 255),
                                    Color(red: 0x9B / 255, green: 0x6D / 255, blue: 0xFF / 255)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 30, height: 30)
                        .overlay(
                            Text("DH")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                        )
                        .scaleEffect(avatarHovered ? 1.05 : 1.0)
                        .animation(.easeOut(duration: 0.15), value: avatarHovered)
                }
                .buttonStyle(.plain)
                .onHover { avatarHovered = $0 }
            }
        }
        .frame(height: 52)
        .padding(.horizontal, Spacing.lg)
        .background(Color.bgSurface)
        .overlay(
            Rectangle()
                .fill(Color.borderSubtle)
                .frame(height: 1),
            alignment: .bottom
        )
    }
}
