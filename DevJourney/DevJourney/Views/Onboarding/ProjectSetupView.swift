import SwiftUI
import Combine

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

    // Provider auth
    @StateObject private var providerAuth = AIProviderAuthService()
    @State private var anthropicKey: String = ""
    @State private var openaiKey: String = ""
    @State private var geminiKey: String = ""
    @State private var showAPIKeyField: [AIProvider: Bool] = [:]

    private let steps = [
        (number: 1, title: "Project", subtitle: "Describe your project"),
        (number: 2, title: "Global Settings", subtitle: "Screen sizes & breakpoints"),
        (number: 3, title: "AI Models", subtitle: "Configure API keys")
    ]

    // Section anchor IDs
    private enum SectionID: Int, CaseIterable {
        case project = 0, globalSettings = 1, aiModels = 2
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

                                sectionDivider

                                aiModelsSection
                                    .id(SectionID.aiModels)
                                    .background(sectionOffsetTracker(SectionID.aiModels))

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
            // Find the section closest to top (with a threshold)
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
        }
        .padding(.horizontal, 24)
        .padding(.top, 32)
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
                        Button(action: { projectType = type }) {
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

    // MARK: - Section 3: AI Models

    private var aiModelsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(
                title: "AI Model Configuration",
                subtitle: "Connect AI providers via OAuth 2.0 or add models with API keys. Model and agent count can be configured per-ticket."
            )

            // Provider cards
            VStack(spacing: 12) {
                providerCard(
                    name: "Anthropic",
                    subtitle: "API Key \u{00B7} Claude Opus 4.6, Sonnet 4.5, Haiku",
                    logoColor: Color(red: 0xD9/255, green: 0x77/255, blue: 0x57/255),
                    logoIcon: "message.fill",
                    provider: .anthropic,
                    apiKey: $anthropicKey
                )

                providerCard(
                    name: "OpenAI",
                    subtitle: "OAuth 2.0 \u{00B7} GPT-4o, o1, o3-mini",
                    logoColor: Color(red: 0x10/255, green: 0xA3/255, blue: 0x7F/255),
                    logoIcon: "sparkles",
                    provider: .openai,
                    apiKey: $openaiKey
                )

                providerCard(
                    name: "Google",
                    subtitle: "OAuth 2.0 \u{00B7} Gemini 2.5 Pro, Flash",
                    logoColor: Color(red: 0x42/255, green: 0x85/255, blue: 0xF4/255),
                    logoIcon: "brain",
                    provider: .gemini,
                    apiKey: $geminiKey
                )
            }

            // Security note
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentGreen)
                Text("OAuth 2.0 tokens are encrypted at rest and auto-refresh. No API keys are stored for OAuth-connected providers.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.accentGreen)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentGreen.opacity(0.08))
            .cornerRadius(Spacing.radiusMd)

            sectionDivider

            // Additional Models via API section
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Additional Models via API")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("Add models from other providers or custom endpoints using an API key.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.textSecondary)
                }

                // Empty state card
                VStack(spacing: 16) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 24))
                        .foregroundColor(.accentPurple)
                        .frame(width: 48, height: 48)
                        .background(Color.accentPurpleDim)
                        .clipShape(Circle())

                    Text("No API models added yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textSecondary)

                    Text("Add models from providers like Mistral, Cohere, or self-hosted endpoints.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.textMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)

                    Button(action: {}) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Add Model via API")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [.accentPurple, Color(red: 0xF4/255, green: 0x72/255, blue: 0xB6/255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(Spacing.radiusMd)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(Color.bgElevated)
                .cornerRadius(Spacing.radiusMd)
                .overlay(RoundedRectangle(cornerRadius: Spacing.radiusMd).stroke(Color.borderSubtle, lineWidth: 1))

                // API note
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.accentOrange)
                    Text("API keys are encrypted at rest and never leave your machine. Prefer OAuth 2.0 when available for automatic token management.")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.accentOrange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentOrange.opacity(0.08))
                .cornerRadius(Spacing.radiusMd)
            }
        }
    }

    // MARK: - Provider Card

    @ViewBuilder
    private func providerCard(
        name: String,
        subtitle: String,
        logoColor: Color,
        logoIcon: String,
        provider: AIProvider,
        apiKey: Binding<String>
    ) -> some View {
        let state = providerAuth.providerStates[provider] ?? .init()
        let hasOAuth = providerAuth.supportsOAuth(provider)
        let isExpanded = showAPIKeyField[provider] == true

        VStack(alignment: .leading, spacing: 0) {
            // Main row: logo + labels + action
            HStack(spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(logoColor)
                            .frame(width: 36, height: 36)
                        Image(systemName: logoIcon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.textMuted)
                    }
                }

                Spacer()

                if providerAuth.isAuthenticating == provider {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if state.isConnected {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.accentGreen)
                        Text("Connected")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accentGreen)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.accentGreen.opacity(0.08))
                    .cornerRadius(100)
                    .overlay(RoundedRectangle(cornerRadius: 100).stroke(Color.accentGreen, lineWidth: 1))
                } else if hasOAuth {
                    // OAuth providers: show sign-in button
                    Button(action: { startOAuth(provider) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.square")
                                .font(.system(size: 14))
                            Text("Sign in with \(name)")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.accentPurple)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.accentPurpleDim)
                        .cornerRadius(100)
                        .overlay(RoundedRectangle(cornerRadius: 100).stroke(Color.accentPurple, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else {
                    // API key only: show connect button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAPIKeyField[provider] = !(showAPIKeyField[provider] ?? false)
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 12))
                            Text("Add API Key")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.accentPurple)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.accentPurpleDim)
                        .cornerRadius(100)
                        .overlay(RoundedRectangle(cornerRadius: 100).stroke(Color.accentPurple, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            // Expandable API key field
            if !state.isConnected && isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if hasOAuth {
                        HStack {
                            Rectangle().fill(Color.borderSubtle).frame(height: 1)
                            Text("or use API key")
                                .font(.system(size: 11))
                                .foregroundColor(.textMuted)
                            Rectangle().fill(Color.borderSubtle).frame(height: 1)
                        }
                    }

                    HStack(spacing: 8) {
                        SecureField(apiKeyPlaceholder(provider), text: apiKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.textPrimary)
                            .padding(10)
                            .background(Color.white.opacity(0.02))
                            .cornerRadius(Spacing.radiusSm)
                            .overlay(RoundedRectangle(cornerRadius: Spacing.radiusSm).stroke(Color.borderSubtle, lineWidth: 1))

                        Button("Connect") {
                            providerAuth.connectWithAPIKey(provider: provider, key: apiKey.wrappedValue)
                            appState.refreshProviderStatuses()
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentPurple)
                        .buttonStyle(.plain)
                        .disabled(apiKey.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            // Error message
            if let error = state.error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.accentRed)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }

            // "Use API key instead" link for OAuth providers
            if hasOAuth && !state.isConnected && !isExpanded {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAPIKeyField[provider] = true
                    }
                }) {
                    Text("Use API key instead")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textMuted)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(Color.bgElevated)
        .cornerRadius(Spacing.radiusMd)
        .overlay(RoundedRectangle(cornerRadius: Spacing.radiusMd).stroke(Color.borderSubtle, lineWidth: 1))
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

    private func toggleScreenSize(_ size: String) {
        if selectedScreenSizes.contains(size) {
            selectedScreenSizes.remove(size)
        } else {
            selectedScreenSizes.insert(size)
        }
    }

    private func startOAuth(_ provider: AIProvider) {
        switch provider {
        case .openai: providerAuth.startOpenAIOAuth()
        case .gemini: providerAuth.startGoogleOAuth()
        case .anthropic: break // No OAuth for Anthropic
        }
    }

    private func apiKeyPlaceholder(_ provider: AIProvider) -> String {
        switch provider {
        case .anthropic: return "sk-ant-..."
        case .openai: return "sk-..."
        case .gemini: return "AIza..."
        }
    }

    private func loadExistingValues() {
        projectDescription = project.projectDescription
        if let pt = ProjectType(rawValue: project.projectType) { projectType = pt }
        selectedScreenSizes = Set(project.screenSizes)
        responsiveBehavior = project.responsiveBehavior
        techStack = project.techStack

        anthropicKey = KeychainService.shared.readAPIKey(for: .anthropic) ?? ""
        openaiKey = KeychainService.shared.readAPIKey(for: .openai) ?? ""
        geminiKey = KeychainService.shared.readAPIKey(for: .gemini) ?? ""
    }

    private func saveSettings() {
        project.projectDescription = projectDescription
        project.projectType = projectType.rawValue
        project.screenSizes = Array(selectedScreenSizes)
        project.responsiveBehavior = responsiveBehavior
        project.techStack = techStack
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
