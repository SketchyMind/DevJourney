import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var projectName: String = ""
    @State private var projectDescription: String = ""
    @State private var projectType: ProjectType = .webApp
    @State private var githubRepo: String = ""
    @State private var selectedScreenSizes: Set<String> = []
    @State private var responsiveBehavior: String = "fluid"
    @State private var techStack: String = ""
    @State private var selectedMobilePlatforms: Set<String> = [MobilePlatform.ios.rawValue, MobilePlatform.android.rawValue]
    @State private var providerKeyInputs: [String: String] = [:]
    @State private var configuredProviderKeys: [String: Bool] = [:]
    @State private var planningProviderConfigId: String = ""
    @State private var planningModelOverride: String = ""
    @State private var designProviderConfigId: String = ""
    @State private var designModelOverride: String = ""
    @State private var devProviderConfigId: String = ""
    @State private var devModelOverride: String = ""
    @State private var debugProviderConfigId: String = ""
    @State private var debugModelOverride: String = ""
    @State private var showValidationError = false
    @State private var showSavedConfirmation = false

    var body: some View {
        ZStack {
            Color.bgApp.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Project Settings")
                        .font(Typography.headingLarge)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Color.bgElevated)
                            .cornerRadius(Spacing.radiusSm)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(Spacing.xl)

                Divider().background(Color.borderSubtle)

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xl) {
                        // Project Name
                        settingsField(title: "Project Name") {
                            TextField("Project name", text: $projectName)
                                .textFieldStyle(.plain)
                                .font(Typography.bodyMedium)
                                .foregroundColor(.textPrimary)
                                .padding(Spacing.md)
                                .background(Color.fieldBg)
                                .cornerRadius(Spacing.radiusMd)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Spacing.radiusMd)
                                        .stroke(showValidationError && projectName.trimmingCharacters(in: .whitespaces).isEmpty
                                                ? Color.fieldBorderError : Color.borderDefault, lineWidth: 1)
                                )

                            if showValidationError && projectName.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text("Project name is required")
                                    .font(Typography.captionLarge)
                                    .foregroundColor(.accentRed)
                            }
                        }

                        // Description
                        settingsField(title: "Description") {
                            TextEditor(text: $projectDescription)
                                .font(Typography.bodyMedium)
                                .foregroundColor(.textPrimary)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 80)
                                .padding(Spacing.md)
                                .background(Color.fieldBg)
                                .cornerRadius(Spacing.radiusMd)
                                .overlay(RoundedRectangle(cornerRadius: Spacing.radiusMd).stroke(Color.borderDefault, lineWidth: 1))
                        }

                        // Project Type Cards
                        settingsField(title: "Project Type") {
                            HStack(spacing: Spacing.md) {
                                ForEach(ProjectType.allCases, id: \.self) { type in
                                    Button(action: { selectProjectType(type) }) {
                                        VStack(spacing: 10) {
                                            Image(systemName: type.iconName)
                                                .font(.system(size: 24))
                                                .foregroundColor(projectType == type ? Color.accentPurple : Color.textSecondary)
                                            Text(type.displayName)
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(projectType == type ? Color.textPrimary : Color.textSecondary)
                                            Text(type.subtitle)
                                                .font(.system(size: 11))
                                                .foregroundColor(.textSecondary)
                                                .multilineTextAlignment(.center)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(projectType == type ? Color.accentPurple.opacity(0.1) : Color.white.opacity(0.03))
                                        .cornerRadius(Spacing.radiusMd)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Spacing.radiusMd)
                                                .stroke(projectType == type ? Color.accentPurple : Color.fieldBorder, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Project Folder
                        settingsField(title: "Project Folder") {
                            HStack(spacing: Spacing.gapSm) {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.accentPurple)
                                Text(appState.currentProject?.folderPath ?? "")
                                    .font(Typography.code)
                                    .foregroundColor(.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.fieldBg)
                            .cornerRadius(Spacing.radiusMd)
                            .overlay(RoundedRectangle(cornerRadius: Spacing.radiusMd).stroke(Color.fieldBorder, lineWidth: 1))
                        }

                        Divider().background(Color.borderSubtle)

                        // GitHub Repo
                        settingsField(title: "GitHub Repository") {
                            TextField("https://github.com/owner/repo", text: $githubRepo)
                                .textFieldStyle(.plain)
                                .font(Typography.bodyMedium)
                                .foregroundColor(.textPrimary)
                                .padding(Spacing.md)
                                .background(Color.fieldBg)
                                .cornerRadius(Spacing.radiusMd)
                                .overlay(RoundedRectangle(cornerRadius: Spacing.radiusMd).stroke(Color.borderDefault, lineWidth: 1))
                        }

                        Divider().background(Color.borderSubtle)

                        if projectType == .mobileApp {
                            settingsField(title: "Mobile Targets") {
                                Text("These platforms will be included automatically in every ticket and agent run.")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.textMuted)

                                HStack(spacing: Spacing.md) {
                                    ForEach(MobilePlatform.allCases, id: \.self) { platform in
                                        Button(action: { toggleMobilePlatform(platform.rawValue) }) {
                                            HStack(spacing: 8) {
                                                Image(systemName: platform.iconName)
                                                    .font(.system(size: 14, weight: .semibold))
                                                Text(platform.displayName)
                                                    .font(Typography.labelSmall)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(Spacing.md)
                                            .background(selectedMobilePlatforms.contains(platform.rawValue) ? Color.accentPurple.opacity(0.1) : Color.white.opacity(0.03))
                                            .foregroundColor(selectedMobilePlatforms.contains(platform.rawValue) ? .textPrimary : .textSecondary)
                                            .cornerRadius(Spacing.radiusMd)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: Spacing.radiusMd)
                                                    .stroke(selectedMobilePlatforms.contains(platform.rawValue) ? Color.accentPurple : Color.fieldBorder, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            Divider().background(Color.borderSubtle)
                        }

                        // Screen Sizes
                        settingsField(title: "Target Screen Sizes") {
                            HStack(spacing: Spacing.md) {
                                ForEach(ScreenSize.allCases, id: \.self) { size in
                                    Button(action: { toggleScreenSize(size.rawValue) }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: selectedScreenSizes.contains(size.rawValue) ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 12, weight: .semibold))
                                            Text(size.shortLabel)
                                                .font(Typography.pillTextMono)
                                        }
                                        .foregroundColor(selectedScreenSizes.contains(size.rawValue) ? Color.accentPurple : Color.textSecondary)
                                        .padding(.horizontal, Spacing.md)
                                        .padding(.vertical, Spacing.gapSm)
                                        .background(selectedScreenSizes.contains(size.rawValue) ? Color.accentPurple.opacity(0.1) : Color.white.opacity(0.03))
                                        .cornerRadius(Spacing.radiusPill)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Spacing.radiusPill)
                                                .stroke(selectedScreenSizes.contains(size.rawValue) ? Color.accentPurple : Color.fieldBorder, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Responsive Behavior
                        settingsField(title: "Responsive Behavior") {
                            HStack(spacing: Spacing.md) {
                                ForEach(ResponsiveBehavior.allCases, id: \.self) { behavior in
                                    Button(action: { responsiveBehavior = behavior.rawValue }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: iconForBehavior(behavior))
                                                .font(.system(size: 16, weight: .semibold))
                                            Text(behavior.displayName)
                                                .font(Typography.labelSmall)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(Spacing.md)
                                        .background(responsiveBehavior == behavior.rawValue ? Color.accentPurple.opacity(0.1) : Color.white.opacity(0.03))
                                        .cornerRadius(Spacing.radiusMd)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Spacing.radiusMd)
                                                .stroke(responsiveBehavior == behavior.rawValue ? Color.accentPurple : Color.fieldBorder, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Tech Stack
                        settingsField(title: "Tech Stack") {
                            TextEditor(text: $techStack)
                                .font(Typography.code)
                                .foregroundColor(.textPrimary)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 60)
                                .padding(Spacing.sm)
                                .background(Color.fieldBg)
                                .cornerRadius(Spacing.radiusMd)
                                .overlay(RoundedRectangle(cornerRadius: Spacing.radiusMd).stroke(Color.fieldBorder, lineWidth: 1))

                            Text("Languages, frameworks, libraries...")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.textMuted)
                        }

                        Divider().background(Color.borderSubtle)

                        if !providerConfigs.isEmpty {
                            Text("Provider Runtime")
                                .font(Typography.headingSmall)
                                .foregroundColor(.textPrimary)

                            ForEach(providerConfigs, id: \.id) { config in
                                providerCard(config)
                            }

                            Divider().background(Color.borderSubtle)

                            Text("Stage Defaults")
                                .font(Typography.headingSmall)
                                .foregroundColor(.textPrimary)

                            stageDefaultRow(
                                stage: .planning,
                                providerId: $planningProviderConfigId,
                                modelOverride: $planningModelOverride
                            )
                            stageDefaultRow(
                                stage: .design,
                                providerId: $designProviderConfigId,
                                modelOverride: $designModelOverride
                            )
                            stageDefaultRow(
                                stage: .dev,
                                providerId: $devProviderConfigId,
                                modelOverride: $devModelOverride
                            )
                            stageDefaultRow(
                                stage: .debug,
                                providerId: $debugProviderConfigId,
                                modelOverride: $debugModelOverride
                            )
                        }

                        Divider().background(Color.borderSubtle)

                        // MCP Server Status
                        settingsField(title: "AI Connection") {
                            let mcpConnected = appState.mcpConnectionStatus.isClientConnected()
                            let claudeMCPReady = appState.claudeMCPRegistrationStatus.isReadyForLocalProjectStore
                            let statusText = mcpConnected
                                ? "Connected to \(appState.mcpConnectionStatus.displayClientName)"
                                : (claudeMCPReady
                                   ? "Claude Code MCP is installed and ready for local tickets"
                                   : "Connect from Claude Code or configure an in-app provider")
                            HStack(spacing: Spacing.md) {
                                Image(systemName: "network")
                                    .font(.system(size: 18))
                                    .foregroundColor(.accentPurple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("MCP Server")
                                        .font(Typography.labelMedium)
                                        .foregroundColor(.textPrimary)
                                    Text(statusText)
                                        .font(.system(size: 11))
                                        .foregroundColor(.textSecondary)
                                }
                                Spacer()
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill((mcpConnected || claudeMCPReady) ? Color.accentGreen : Color.textMuted)
                                        .frame(width: 8, height: 8)
                                    Text(mcpConnected ? "Connected" : (claudeMCPReady ? "Ready" : "Idle"))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor((mcpConnected || claudeMCPReady) ? .accentGreen : .textMuted)
                                }
                            }
                            .padding(Spacing.md)
                            .background(Color.fieldBg)
                            .cornerRadius(Spacing.radiusMd)
                            .overlay(RoundedRectangle(cornerRadius: Spacing.radiusMd).stroke(Color.fieldBorder, lineWidth: 1))
                        }
                    }
                    .padding(Spacing.xl)
                }

                Divider().background(Color.borderSubtle)

                // Footer
                HStack(spacing: Spacing.gapMd) {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Text("Cancel")
                            .font(Typography.buttonSecondary)
                            .foregroundColor(.textSecondary)
                            .frame(height: Spacing.buttonHeight)
                            .padding(.horizontal, Spacing.xl)
                            .background(Color.bgElevated)
                            .cornerRadius(Spacing.radiusMd)
                    }
                    .buttonStyle(.plain)

                    Button(action: saveSettings) {
                        Text("Save")
                            .font(Typography.buttonSecondary)
                            .foregroundColor(.bgApp)
                            .frame(height: Spacing.buttonHeight)
                            .padding(.horizontal, Spacing.xl)
                            .background(Color.accentPurple)
                            .cornerRadius(Spacing.radiusMd)
                    }
                    .buttonStyle(.plain)
                }
                .padding(Spacing.xl)
            }

            if showSavedConfirmation {
                VStack {
                    Spacer()
                    Text("Settings saved")
                        .font(Typography.labelMedium)
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.accentGreen.opacity(0.9))
                        .cornerRadius(Spacing.radiusMd)
                        .padding(.bottom, Spacing.xxl)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 480, minHeight: 560)
        .frame(idealWidth: Spacing.settingsModalWidth)
        .onAppear(perform: loadCurrentValues)
    }

    // MARK: - Components

    private func settingsField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.gapSm) {
            Text(title)
                .font(Typography.labelMedium)
                .foregroundColor(.textMuted)
            content()
        }
    }

    private var providerConfigs: [AIProviderConfig] {
        guard let project = appState.currentProject else { return [] }
        return project.providerConfigs.sorted { lhs, rhs in
            lhs.kindEnum.displayName < rhs.kindEnum.displayName
        }
    }

    private var enabledProviderConfigs: [AIProviderConfig] {
        providerConfigs.filter(\.enabled)
    }

    @ViewBuilder
    private func providerCard(_ config: AIProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: config.kindEnum.iconName)
                    .font(.system(size: 16))
                    .foregroundColor(.accentPurple)
                    .frame(width: 28, height: 28)
                    .background(Color.accentPurple.opacity(0.12))
                    .cornerRadius(8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(config.displayName)
                        .font(Typography.labelMedium)
                        .foregroundColor(.textPrimary)
                    Text(config.kindEnum.displayName)
                        .font(Typography.captionLarge)
                        .foregroundColor(.textMuted)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { config.enabled },
                    set: {
                        config.enabled = $0
                        config.touch()
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            if config.kindEnum.supportsCustomBaseURL {
                TextField("Provider name", text: Binding(
                    get: { config.displayName },
                    set: {
                        config.displayName = $0
                        config.touch()
                    }
                ))
                .textFieldStyle(.plain)
                .font(Typography.bodySmall)
                .foregroundColor(.textPrimary)
                .padding(Spacing.sm)
                .background(Color.fieldBg)
                .cornerRadius(Spacing.radiusSm)
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radiusSm)
                        .stroke(Color.fieldBorder, lineWidth: 1)
                )

                TextField("https://your-compatible-endpoint/v1", text: Binding(
                    get: { config.baseURL ?? "" },
                    set: {
                        config.baseURL = $0
                        config.touch()
                    }
                ))
                .textFieldStyle(.plain)
                .font(Typography.code)
                .foregroundColor(.textPrimary)
                .padding(Spacing.sm)
                .background(Color.fieldBg)
                .cornerRadius(Spacing.radiusSm)
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radiusSm)
                        .stroke(Color.fieldBorder, lineWidth: 1)
                )
            }

            TextField("Default model", text: Binding(
                get: { config.defaultModel },
                set: {
                    config.defaultModel = $0
                    config.touch()
                }
            ))
            .textFieldStyle(.plain)
            .font(Typography.code)
            .foregroundColor(.textPrimary)
            .padding(Spacing.sm)
            .background(Color.fieldBg)
            .cornerRadius(Spacing.radiusSm)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusSm)
                    .stroke(Color.fieldBorder, lineWidth: 1)
            )

            HStack(spacing: Spacing.gapSm) {
                if configuredProviderKeys[config.id] == true {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentGreen)
                        Text("API key configured")
                            .font(Typography.captionLarge)
                            .foregroundColor(.accentGreen)
                    }

                    Spacer()

                    Button("Remove Key") {
                        removeProviderKey(config)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentRed)
                    .buttonStyle(.plain)
                } else {
                    SecureField("API key", text: bindingForProviderKey(config.id))
                        .textFieldStyle(.plain)
                        .font(Typography.code)
                        .foregroundColor(.textPrimary)
                        .padding(Spacing.sm)
                        .background(Color.fieldBg)
                        .cornerRadius(Spacing.radiusSm)
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.radiusSm)
                                .stroke(Color.fieldBorder, lineWidth: 1)
                        )

                    Button("Save Key") {
                        saveProviderKey(config)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentPurple)
                    .buttonStyle(.plain)
                    .disabled((providerKeyInputs[config.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.bgElevated)
        .cornerRadius(Spacing.radiusMd)
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.radiusMd)
                .stroke(Color.borderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func stageDefaultRow(
        stage: Stage,
        providerId: Binding<String>,
        modelOverride: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.gapSm) {
            Text(stage.displayName)
                .font(Typography.labelMedium)
                .foregroundColor(.textPrimary)

            HStack(spacing: Spacing.md) {
                Picker("", selection: providerId) {
                    Text("Select provider").tag("")
                    ForEach(enabledProviderConfigs, id: \.id) { config in
                        Text(config.displayName).tag(config.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(.accentPurple)

                TextField("Model override (optional)", text: modelOverride)
                    .textFieldStyle(.plain)
                    .font(Typography.code)
                    .foregroundColor(.textPrimary)
                    .padding(Spacing.sm)
                    .background(Color.fieldBg)
                    .cornerRadius(Spacing.radiusSm)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.radiusSm)
                            .stroke(Color.fieldBorder, lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Helpers

    private func iconForBehavior(_ behavior: ResponsiveBehavior) -> String {
        switch behavior {
        case .fluid: return "square.resize"
        case .fixed: return "square"
        case .breakpoints: return "square.split.2x1"
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

    private func bindingForProviderKey(_ providerId: String) -> Binding<String> {
        Binding(
            get: { providerKeyInputs[providerId] ?? "" },
            set: { providerKeyInputs[providerId] = $0 }
        )
    }

    private func saveProviderKey(_ config: AIProviderConfig) {
        let trimmed = (providerKeyInputs[config.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try? KeychainService.shared.saveProviderAPIKey(trimmed, reference: config.apiKeyReference)
        providerKeyInputs[config.id] = ""
        configuredProviderKeys[config.id] = true
    }

    private func removeProviderKey(_ config: AIProviderConfig) {
        try? KeychainService.shared.deleteProviderAPIKey(reference: config.apiKeyReference)
        configuredProviderKeys[config.id] = false
    }

    private func loadCurrentValues() {
        guard let project = appState.currentProject else { return }
        appState.projectService.ensureDefaultProviderConfigs(for: project)
        projectName = project.name
        projectDescription = project.projectDescription
        projectType = ProjectType(rawValue: project.projectType) ?? .other
        githubRepo = project.githubRepo ?? ""
        selectedScreenSizes = Set(project.screenSizes)
        responsiveBehavior = project.responsiveBehavior
        techStack = project.techStack
        let storedPlatforms = Set(project.normalizedMobilePlatforms)
        selectedMobilePlatforms = storedPlatforms.isEmpty
            ? [MobilePlatform.ios.rawValue, MobilePlatform.android.rawValue]
            : storedPlatforms
        planningProviderConfigId = project.planningProviderConfigId ?? ""
        planningModelOverride = project.planningModelOverride
        designProviderConfigId = project.designProviderConfigId ?? ""
        designModelOverride = project.designModelOverride
        devProviderConfigId = project.devProviderConfigId ?? ""
        devModelOverride = project.devModelOverride
        debugProviderConfigId = project.debugProviderConfigId ?? ""
        debugModelOverride = project.debugModelOverride

        providerKeyInputs = [:]
        configuredProviderKeys = Dictionary(uniqueKeysWithValues: providerConfigs.map { config in
            (config.id, KeychainService.shared.readProviderAPIKey(reference: config.apiKeyReference) != nil)
        })
    }

    private func saveSettings() {
        let trimmedName = projectName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            showValidationError = true
            return
        }

        guard let project = appState.currentProject else { return }

        project.planningProviderConfigId = planningProviderConfigId.isEmpty ? nil : planningProviderConfigId
        project.planningModelOverride = planningModelOverride
        project.designProviderConfigId = designProviderConfigId.isEmpty ? nil : designProviderConfigId
        project.designModelOverride = designModelOverride
        project.devProviderConfigId = devProviderConfigId.isEmpty ? nil : devProviderConfigId
        project.devModelOverride = devModelOverride
        project.debugProviderConfigId = debugProviderConfigId.isEmpty ? nil : debugProviderConfigId
        project.debugModelOverride = debugModelOverride

        appState.projectService.updateProjectSettings(
            project,
            name: trimmedName,
            description: projectDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            projectType: projectType.rawValue,
            githubRepo: githubRepo.isEmpty ? nil : githubRepo,
            screenSizes: Array(selectedScreenSizes),
            responsiveBehavior: responsiveBehavior,
            techStack: techStack,
            mobilePlatforms: Array(selectedMobilePlatforms)
        )

        withAnimation(.contentTransition) {
            showSavedConfirmation = true
        }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.contentTransition) {
                showSavedConfirmation = false
            }
            dismiss()
        }
    }
}
