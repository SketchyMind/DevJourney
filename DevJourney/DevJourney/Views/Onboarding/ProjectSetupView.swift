import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct ProjectSetupView: View {
    @EnvironmentObject var appState: AppState
    let project: Project
    var onComplete: () -> Void
    var onSkip: () -> Void

    @State private var activeSection = 0
    @State private var projectDescription: String = ""
    @State private var projectType: ProjectType = .webApp
    @State private var selectedScreenSizes: Set<String> = ["mobile", "tablet", "desktop"]
    @State private var responsiveBehavior: String = "fluid"
    @State private var techStack: String = ""
    @State private var selectedMobilePlatforms: Set<String> = [MobilePlatform.ios.rawValue, MobilePlatform.android.rawValue]
    @State private var mcpCopied: Bool = false

    private let steps = [
        (number: 1, title: "Project", subtitle: "Describe your project"),
        (number: 2, title: "Global Settings", subtitle: "Screen sizes & breakpoints")
    ]

    // Section anchor IDs
    private enum SectionID: Int, CaseIterable {
        case project = 0, globalSettings = 1
    }

    var body: some View {
        ZStack {
            Color.bgApp.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Fixed Sidebar (280pt per design)
                    sidebar
                        .frame(width: 280)
                        .background(Color.bgSurface)
                        .overlay(Rectangle().fill(Color.borderSubtle).frame(width: 1), alignment: .trailing)

                    // Main Content - full width with scroll tracking
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 32) {
                                projectSection
                                    .id(SectionID.project)
                                    .background(sectionOffsetTracker(SectionID.project))

                                sectionDivider

                                globalSettingsSection
                                    .id(SectionID.globalSettings)
                                    .background(sectionOffsetTracker(SectionID.globalSettings))

                                // MCP connection info
                                mcpInfoSection

                                // Extra padding at bottom for scroll room
                                Color.clear.frame(height: 100)
                            }
                            .padding(.horizontal, 60)
                            .padding(.top, 40)
                        }
                        .coordinateSpace(name: "scroll")
                        .onChange(of: activeSection) { _, newSection in
                            if let id = SectionID(rawValue: newSection) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo(id, anchor: .top)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Sticky Bottom Bar (72pt per design)
                bottomBar
            }
        }
        .onAppear { loadExistingValues() }
    }

    // MARK: - Scroll Tracking

    private func sectionOffsetTracker(_ section: SectionID) -> some View {
        GeometryReader { geo in
            let offset = geo.frame(in: .named("scroll")).minY
            Color.clear
                .preference(key: SectionOffsetKey.self, value: [section.rawValue: offset])
        }
        .frame(height: 0)
        .onPreferenceChange(SectionOffsetKey.self) { offsets in
            let sorted = offsets.sorted { $0.value < $1.value }
            if let closest = sorted.first(where: { $0.value > -100 }) ?? sorted.last {
                if activeSection != closest.key {
                    activeSection = closest.key
                }
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Project Setup")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("Configure your workspace")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.textSecondary)
            }

            VStack(spacing: 0) {
                ForEach(steps, id: \.number) { step in
                    let isActive = activeSection == step.number - 1
                    Button(action: { activeSection = step.number - 1 }) {
                        HStack(spacing: 12) {
                            Text("\(step.number)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(isActive ? .bgApp : .textMuted)
                                .frame(width: 28, height: 28)
                                .background(isActive ? Color.accentPurple : Color.white.opacity(0.05))
                                .overlay(
                                    Circle().strokeBorder(isActive ? Color.clear : Color.borderSubtle, lineWidth: 1)
                                )
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(isActive ? .textPrimary : .textMuted)
                                Text(step.subtitle)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.textMuted)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isActive ? Color.accentPurpleDim : Color.clear)
                        .cornerRadius(Spacing.radiusMd)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Step \(step.number), \(step.title)")
                }
            }

            Spacer()

            // MCP status indicator
            HStack(spacing: 8) {
                let mcpConnected = appState.mcpConnectionStatus.isClientConnected()
                let claudeMCPReady = appState.claudeMCPRegistrationStatus.isReadyForLocalProjectStore
                Circle()
                    .fill((mcpConnected || claudeMCPReady) ? Color.accentGreen : Color.textMuted)
                    .frame(width: 8, height: 8)
                Text(
                    mcpConnected
                    ? "\(appState.mcpConnectionStatus.displayClientName) connected"
                    : (claudeMCPReady ? "Claude MCP ready" : "MCP client idle")
                )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textMuted)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
        .padding(.bottom, 16)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Button(action: onSkip) {
                Text("Skip Setup")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip Setup")

            Spacer()

            Button(action: {
                saveSettings()
                onComplete()
            }) {
                HStack(spacing: 8) {
                    Text("Start Building")
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [.accentPurple, Color(red: 0xF4/255, green: 0x72/255, blue: 0xB6/255)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(Spacing.radiusMd)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start Building")
        }
        .padding(.horizontal, 60)
        .frame(height: 72)
        .background(Color.bgApp)
        .overlay(Rectangle().fill(Color.borderSubtle).frame(height: 1), alignment: .top)
    }

    // MARK: - Section Divider

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 1)
    }

    // MARK: - Section 1: Project

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "What are you building?",
                subtitle: "Tell us about your project so the agents can work effectively on every ticket."
            )

            fieldGroup(title: "Project Name") {
                HStack {
                    Text(project.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 44)
                .padding(.horizontal, 16)
                .background(Color.white.opacity(0.02))
                .cornerRadius(Spacing.radiusMd)
                .overlay(RoundedRectangle(cornerRadius: Spacing.radiusMd).stroke(Color.borderSubtle, lineWidth: 1))
            }

            fieldGroup(title: "Project Description") {
                Text("Describe what you want to build. This context will be included in every ticket for the agents.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.textMuted)

                TextEditor(text: $projectDescription)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100)
                    .padding(16)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(Spacing.radiusMd)
                    .overlay(RoundedRectangle(cornerRadius: Spacing.radiusMd).stroke(Color.borderSubtle, lineWidth: 1))
            }

            fieldGroup(title: "Project Type") {
                HStack(spacing: 12) {
                    ForEach(ProjectType.allCases, id: \.self) { type in
                        let isSelected = projectType == type
                        Button(action: { selectProjectType(type) }) {
                            VStack(spacing: 10) {
                                Image(systemName: type.iconName)
                                    .font(.system(size: 28))
                                    .foregroundColor(isSelected ? .accentPurple : .textSecondary)
                                Text(type.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                Text(type.subtitle)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(isSelected ? Color.accentPurpleDim : Color.white.opacity(0.02))
                            .cornerRadius(Spacing.radiusMd)
                            .overlay(
                                RoundedRectangle(cornerRadius: Spacing.radiusMd)
                                    .stroke(isSelected ? Color.accentPurple : Color.borderSubtle,
                                            lineWidth: isSelected ? 1.5 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Section 2: Global Settings

    private var globalSettingsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "Global Project Settings",
                subtitle: "These settings apply to every ticket and are shared with all agents."
            )

            if projectType == .mobileApp {
                fieldGroup(title: "Mobile Targets") {
                    Text("Choose the platforms this project should support. These targets will be included in every ticket context.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.textMuted)

                    HStack(spacing: 10) {
                        ForEach(MobilePlatform.allCases, id: \.self) { platform in
                            let isSelected = selectedMobilePlatforms.contains(platform.rawValue)
                            Button(action: { toggleMobilePlatform(platform.rawValue) }) {
                                HStack(spacing: 8) {
                                    Image(systemName: platform.iconName)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(platform.displayName)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(isSelected ? Color.accentPurpleDim : Color.white.opacity(0.02))
                                .foregroundColor(isSelected ? .textPrimary : .textSecondary)
                                .cornerRadius(Spacing.radiusMd)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Spacing.radiusMd)
                                        .stroke(isSelected ? Color.accentPurple : Color.borderSubtle, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            fieldGroup(title: "Target Screen Sizes") {
                HStack(spacing: 8) {
                    ForEach(ScreenSize.allCases, id: \.self) { size in
                        let isSelected = selectedScreenSizes.contains(size.rawValue)
                        Button(action: { toggleScreenSize(size.rawValue) }) {
                            HStack(spacing: 6) {
                                Image(systemName: screenSizeIcon(size))
                                    .font(.system(size: 14))
                                    .foregroundColor(isSelected ? .accentPurple : .textMuted)
                                Text(size.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(isSelected ? .textPrimary : .textMuted)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color.accentPurpleDim : Color.white.opacity(0.02))
                            .cornerRadius(100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 100)
                                    .stroke(isSelected ? Color.accentPurple : Color.borderSubtle, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // Custom pill
                    Button(action: {}) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 14))
                            Text("Custom")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.textMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.02))
                        .cornerRadius(100)
                        .overlay(RoundedRectangle(cornerRadius: 100).stroke(Color.borderSubtle, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            fieldGroup(title: "Responsive Behavior") {
                HStack(spacing: 10) {
                    ForEach(ResponsiveBehavior.allCases, id: \.self) { behavior in
                        let isSelected = responsiveBehavior == behavior.rawValue
                        Button(action: { responsiveBehavior = behavior.rawValue }) {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(systemName: responsiveBehaviorIcon(behavior))
                                    .font(.system(size: 20))
                                    .foregroundColor(isSelected ? .accentPurple : .textSecondary)
                                Text(behavior.displayName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(isSelected ? Color.accentPurpleDim : Color.white.opacity(0.02))
                            .cornerRadius(Spacing.radiusMd)
                            .overlay(
                                RoundedRectangle(cornerRadius: Spacing.radiusMd)
                                    .stroke(isSelected ? Color.accentPurple : Color.borderSubtle, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            fieldGroup(title: "Tech Stack (optional)") {
                HStack {
                    TextField("e.g. Next.js, Tailwind CSS, PostgreSQL, Supabase...", text: $techStack)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textPrimary)
                }
                .frame(height: 44)
                .padding(.horizontal, 16)
                .background(Color.white.opacity(0.02))
                .cornerRadius(Spacing.radiusMd)
                .overlay(RoundedRectangle(cornerRadius: Spacing.radiusMd).stroke(Color.borderSubtle, lineWidth: 1))
            }
        }
    }

    // MARK: - MCP Info Section

    private var mcpInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionDivider

            sectionHeader(
                title: "AI Connection",
                subtitle: "DevJourney works as an MCP server. Connect it from Claude Desktop, Cursor, or any MCP-compatible AI client."
            )

            // Connection instructions
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "network")
                        .font(.system(size: 24))
                        .foregroundColor(.accentPurple)
                        .frame(width: 44, height: 44)
                        .background(Color.accentPurpleDim)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("MCP Server")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text("Add DevJourney to your AI client's MCP config to get started.")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.textSecondary)
                    }
                }

                // Config snippet with copy button
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Add this to your AI client's MCP config:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textMuted)
                        Spacer()
                        Button(action: copyMCPConfig) {
                            HStack(spacing: 4) {
                                Image(systemName: mcpCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11, weight: .medium))
                                Text(mcpCopied ? "Copied!" : "Copy")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(mcpCopied ? .accentGreen : .accentPurple)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(mcpCopied ? Color.accentGreen.opacity(0.1) : Color.accentPurpleDim)
                            .cornerRadius(Spacing.radiusSm)
                        }
                        .buttonStyle(.plain)
                    }
                    Text(mcpConfigString)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.02))
                    .cornerRadius(Spacing.radiusSm)
                    .overlay(RoundedRectangle(cornerRadius: Spacing.radiusSm).stroke(Color.borderSubtle, lineWidth: 1))
                }
            }
            .padding(16)
            .background(Color.bgElevated)
            .cornerRadius(Spacing.radiusMd)
            .overlay(RoundedRectangle(cornerRadius: Spacing.radiusMd).stroke(Color.borderSubtle, lineWidth: 1))

            // Info note
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentPurple)
                Text("Your AI client (Claude, GPT, Gemini, etc.) handles the model selection. DevJourney focuses on project management and workflow.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.accentPurple)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentPurple.opacity(0.08))
            .cornerRadius(Spacing.radiusMd)
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.textPrimary)
            Text(subtitle)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func fieldGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textSecondary)
                .tracking(0.5)
            content()
        }
    }

    // MARK: - Helpers

    private func screenSizeIcon(_ size: ScreenSize) -> String {
        switch size {
        case .mobile: return "iphone"
        case .tablet: return "ipad"
        case .desktop: return "desktopcomputer"
        }
    }

    private func responsiveBehaviorIcon(_ behavior: ResponsiveBehavior) -> String {
        switch behavior {
        case .fluid: return "arrow.up.left.and.arrow.down.right"
        case .fixed: return "square"
        case .breakpoints: return "rectangle.split.3x1"
        }
    }

    private var mcpConfigString: String {
        let execPath = MCPLaunchService.shared.stableCommandPath()
        return """
        {
          "mcpServers": {
            "devjourney": {
              "command": "\(execPath)",
              "args": ["--mcp"]
            }
          }
        }
        """
    }

    private func copyMCPConfig() {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(mcpConfigString, forType: .string)
        #endif
        mcpCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            mcpCopied = false
        }
    }

    private func toggleScreenSize(_ size: String) {
        if selectedScreenSizes.contains(size) {
            selectedScreenSizes.remove(size)
        } else {
            selectedScreenSizes.insert(size)
        }
    }

    private func toggleMobilePlatform(_ platform: String) {
        if selectedMobilePlatforms.contains(platform) {
            if selectedMobilePlatforms.count > 1 {
                selectedMobilePlatforms.remove(platform)
            }
        } else {
            selectedMobilePlatforms.insert(platform)
        }
    }

    private func selectProjectType(_ type: ProjectType) {
        projectType = type
        if type == .mobileApp, selectedMobilePlatforms.isEmpty {
            selectedMobilePlatforms = [MobilePlatform.ios.rawValue, MobilePlatform.android.rawValue]
        }
    }

    private func loadExistingValues() {
        projectDescription = project.projectDescription
        if let pt = ProjectType(rawValue: project.projectType) { projectType = pt }
        selectedScreenSizes = Set(project.screenSizes)
        responsiveBehavior = project.responsiveBehavior
        techStack = project.techStack
        let storedPlatforms = Set(project.normalizedMobilePlatforms)
        selectedMobilePlatforms = storedPlatforms.isEmpty
            ? [MobilePlatform.ios.rawValue, MobilePlatform.android.rawValue]
            : storedPlatforms
    }

    private func saveSettings() {
        project.projectDescription = projectDescription
        project.projectType = projectType.rawValue
        project.screenSizes = Array(selectedScreenSizes)
        project.responsiveBehavior = responsiveBehavior
        project.techStack = techStack
        project.mobilePlatforms = projectType == .mobileApp ? Array(selectedMobilePlatforms) : []
        appState.projectService.updateProject(project)
    }
}

// MARK: - Preference Key for scroll tracking

private struct SectionOffsetKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
