import SwiftUI

struct Typography {
    // Display styles (large headings)
    static let displayLarge = Font.system(size: 32, weight: .bold, design: .default)
    static let displayMedium = Font.system(size: 28, weight: .bold, design: .default)
    static let displaySmall = Font.system(size: 24, weight: .bold, design: .default)

    // Heading styles
    static let headingLarge = Font.system(size: 20, weight: .semibold, design: .default)
    static let headingMedium = Font.system(size: 18, weight: .semibold, design: .default)
    static let headingSmall = Font.system(size: 16, weight: .semibold, design: .default)

    // Body styles
    static let bodyLarge = Font.system(size: 16, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 14, weight: .regular, design: .default)
    static let bodySmall = Font.system(size: 12, weight: .regular, design: .default)

    // Label styles
    static let labelLarge = Font.system(size: 14, weight: .medium, design: .default)
    static let labelMedium = Font.system(size: 12, weight: .medium, design: .default)
    static let labelSmall = Font.system(size: 11, weight: .medium, design: .default)

    // Caption styles
    static let captionLarge = Font.system(size: 12, weight: .regular, design: .default)
    static let captionSmall = Font.system(size: 10, weight: .regular, design: .default)

    // Code style
    static let code = Font.system(size: 12, weight: .regular, design: .monospaced)

    // Button styles
    static let buttonPrimary = Font.system(size: 16, weight: .semibold)
    static let buttonSecondary = Font.system(size: 14, weight: .medium)

    // Pill styles
    static let pillText = Font.system(size: 12, weight: .medium)
    static let pillTextMono = Font.system(size: 11, weight: .medium, design: .monospaced)

    // Badge style
    static let badgeText = Font.system(size: 10, weight: .semibold)
}

extension View {
    func headingStyle(_ size: HeadingSize = .medium) -> some View {
        switch size {
        case .large:
            return self.font(Typography.headingLarge)
        case .medium:
            return self.font(Typography.headingMedium)
        case .small:
            return self.font(Typography.headingSmall)
        }
    }

    func bodyStyle(_ size: BodySize = .medium) -> some View {
        switch size {
        case .large:
            return self.font(Typography.bodyLarge)
        case .medium:
            return self.font(Typography.bodyMedium)
        case .small:
            return self.font(Typography.bodySmall)
        }
    }

    func labelStyle(_ size: LabelSize = .medium) -> some View {
        switch size {
        case .large:
            return self.font(Typography.labelLarge)
        case .medium:
            return self.font(Typography.labelMedium)
        case .small:
            return self.font(Typography.labelSmall)
        }
    }
}

enum HeadingSize {
    case large, medium, small
}

enum BodySize {
    case large, medium, small
}

enum LabelSize {
    case large, medium, small
}
