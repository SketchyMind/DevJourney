import SwiftUI

struct PanelContainer<Content: View>: View {
    let title: String
    @Binding var isPresented: Bool
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Spacer()

                // Panel
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Text(title)
                            .font(Typography.headingMedium)
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.textSecondary)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: Spacing.radiusSm))
                                .overlay(RoundedRectangle(cornerRadius: Spacing.radiusSm).strokeBorder(Color.borderSubtle, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.lg)

                    Rectangle()
                        .fill(Color.borderSubtle)
                        .frame(height: 1)

                    // Content
                    ScrollView {
                        content
                            .padding(.horizontal, Spacing.xl)
                            .padding(.vertical, Spacing.lg)
                    }
                }
                .frame(width: min(max(geometry.size.width * 2 / 3, 520), Spacing.panelMaxWidth))
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
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isPresented = false
        }
    }
}
