import SwiftUI

extension Color {
    // Background Colors
    static let bgApp = Color(red: 0x0D / 255, green: 0x0B / 255, blue: 0x0F / 255)
    static let bgSurface = Color(red: 0x1A / 255, green: 0x17 / 255, blue: 0x20 / 255)
    static let bgElevated = Color(red: 0x23 / 255, green: 0x1F / 255, blue: 0x2B / 255)
    static let bgCard = Color(red: 0x14 / 255, green: 0x11 / 255, blue: 0x18 / 255)

    // Text Colors
    static let textPrimary = Color(red: 0xF0 / 255, green: 0xEC / 255, blue: 0xF4 / 255)
    static let textSecondary = Color(red: 0x8A / 255, green: 0x84 / 255, blue: 0x94 / 255)
    static let textMuted = Color(red: 0x5C / 255, green: 0x56 / 255, blue: 0x6A / 255)

    // Border Colors
    static let borderSubtle = Color(red: 0x2A / 255, green: 0x25 / 255, blue: 0x35 / 255)
    static let borderDefault = Color(red: 0x35 / 255, green: 0x2F / 255, blue: 0x42 / 255)

    // Accent Colors
    static let accentPurple = Color(red: 0x9B / 255, green: 0x6D / 255, blue: 0xFF / 255)
    static let accentBlue = Color(red: 0x60 / 255, green: 0xA5 / 255, blue: 0xFA / 255)
    static let accentYellow = Color(red: 0xFB / 255, green: 0xBF / 255, blue: 0x24 / 255)
    static let accentOrange = Color(red: 0xFB / 255, green: 0x92 / 255, blue: 0x3C / 255)
    static let accentGreen = Color(red: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255)
    static let accentRed = Color(red: 0xF8 / 255, green: 0x71 / 255, blue: 0x71 / 255)

    // Agent Colors
    static let agentMechanic = Color(red: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255)
    static let agentMechanicDim = Color(red: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255).opacity(0.30)

    // Dim Variants (from pencil design)
    static let accentPurpleDim = Color(red: 0x9B / 255, green: 0x6D / 255, blue: 0xFF / 255).opacity(0.1875) // 0x30/255
    static let accentBlueDim = Color(red: 0x60 / 255, green: 0xA5 / 255, blue: 0xFA / 255).opacity(0.1875)
    static let accentYellowDim = Color(red: 0xFB / 255, green: 0xBF / 255, blue: 0x24 / 255).opacity(0.1875)
    static let accentOrangeDim = Color(red: 0xFB / 255, green: 0x92 / 255, blue: 0x3C / 255).opacity(0.1875)
    static let accentGreenDim = Color(red: 0x4A / 255, green: 0xDE / 255, blue: 0x80 / 255).opacity(0.1875)
    static let accentRedDim = Color(red: 0xF8 / 255, green: 0x71 / 255, blue: 0x71 / 255).opacity(0.1875)

    // Card colors (from pencil design)
    static let cardFill = Color.white.opacity(0.05) // #ffffff0d
    static let cardBorder = Color.white.opacity(0.15) // #ffffff26
    static let buttonGlassEffect = Color.white.opacity(0.08) // #ffffff14

    // Field colors
    static let fieldBg = Color.bgCard
    static let fieldBorder = Color.borderSubtle
    static let fieldBorderFocus = Color.borderDefault
    static let fieldBorderError = Color.accentRed
    static let overlayBackdrop = Color.black.opacity(0.4)
    static let emptyStateBg = Color.white.opacity(0.02)

    // Stage Colors
    func colorForStage(_ stage: Stage) -> Color {
        switch stage {
        case .backlog:
            return .textMuted
        case .planning:
            return .accentPurple
        case .design:
            return .accentBlue
        case .dev:
            return .accentYellow
        case .debug:
            return .accentOrange
        case .complete:
            return .accentGreen
        }
    }

    func colorForStageDim(_ stage: Stage) -> Color {
        switch stage {
        case .backlog:
            return .borderSubtle
        case .planning:
            return .accentPurpleDim
        case .design:
            return .accentBlueDim
        case .dev:
            return .accentYellowDim
        case .debug:
            return .accentOrangeDim
        case .complete:
            return .accentGreenDim
        }
    }
}
