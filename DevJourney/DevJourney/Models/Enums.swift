import Foundation
import SwiftData

enum Stage: String, Codable, CaseIterable {
    case backlog = "Backlog"
    case planning = "Planning"
    case design = "Design"
    case dev = "Dev"
    case debug = "Debug"
    case complete = "Complete"

    var displayName: String { self.rawValue }
    var index: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    func nextStage() -> Stage? {
        guard let currentIndex = Stage.allCases.firstIndex(of: self),
              currentIndex < Stage.allCases.count - 1 else {
            return nil
        }
        return Stage.allCases[currentIndex + 1]
    }
}

enum TicketStatus: String, Codable, CaseIterable {
    case inactive = "Inactive"
    case ready = "Ready"
    case active = "Active"
    case clarify = "Clarify"
    case done = "Done"
    case complete = "Complete"

    var displayName: String { self.rawValue }
}

enum Priority: String, Codable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    var displayName: String { self.rawValue }
}

enum ProjectType: String, Codable, CaseIterable {
    case webApp = "Web App"
    case mobileApp = "Mobile App"
    case desktopApp = "Desktop App"
    case other = "Other"

    var displayName: String { self.rawValue }

    var subtitle: String {
        switch self {
        case .webApp: return "Responsive web application"
        case .mobileApp: return "iOS or Android native"
        case .desktopApp: return "Local desktop application"
        case .other: return "CLI, API, library, etc."
        }
    }

    var iconName: String {
        switch self {
        case .webApp: return "globe"
        case .mobileApp: return "iphone"
        case .desktopApp: return "desktopcomputer"
        case .other: return "shippingbox"
        }
    }
}

enum RepoVisibility: String, Codable, CaseIterable, Sendable {
    case `private` = "private"
    case `public` = "public"

    var displayName: String {
        switch self {
        case .private: return "Private"
        case .public: return "Public"
        }
    }
}

enum ResponsiveBehavior: String, Codable, CaseIterable, Sendable {
    case fluid = "fluid"
    case fixed = "fixed"
    case breakpoints = "breakpoints"

    var displayName: String {
        switch self {
        case .fluid: return "Fluid / Responsive"
        case .fixed: return "Fixed Width"
        case .breakpoints: return "Breakpoints"
        }
    }
}

enum ScreenSize: String, Codable, CaseIterable, Sendable {
    case mobile = "mobile"
    case tablet = "tablet"
    case desktop = "desktop"

    var displayName: String {
        switch self {
        case .mobile: return "Mobile (375px)"
        case .tablet: return "Tablet (768px)"
        case .desktop: return "Desktop (1440px)"
        }
    }

    var shortLabel: String {
        switch self {
        case .mobile: return "M"
        case .tablet: return "T"
        case .desktop: return "D"
        }
    }
}

enum MobilePlatform: String, Codable, CaseIterable, Sendable {
    case ios = "ios"
    case android = "android"

    var displayName: String {
        switch self {
        case .ios: return "iOS"
        case .android: return "Android"
        }
    }

    var iconName: String {
        switch self {
        case .ios: return "iphone"
        case .android: return "apple.terminal.on.rectangle"
        }
    }
}
