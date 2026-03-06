import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var projectName: String = ""
    @State private var projectDescription: String = ""
    @State private var projectType: ProjectType = .webApp
    @State private var defaultModel: String = "claude-sonnet-4-5-20251001"
    @State private var defaultProvider: String = "anthropic"
    @State private var githubRepo: String = ""
    @State private var selectedScreenSizes: Set<String> = []
    @State private var responsiveBehavior: String = "fluid"
    @State private var techStack: String = ""

    @StateObject private var providerAuth = AIProviderAuthService()
    @State private var anthropicKey: String = ""
    @State private var openaiKey: String = ""
    @State private var geminiKey: String = ""

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
                                    Button(action: { projectType = type }) {
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

                        // Default Model
                        settingsField(title: "Default AI Model") {
                            Picker("", selection: $defaultModel) {
                                ForEach(AIModelConfig.allModels, id: \.id) { model in
                                    Text(model.displayName).tag(model.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(.accentPurple)
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

                        // API Keys Section
                        Text("AI Provider Keys")
                            .font(Typography.headingSmall)
                            .foregroundColor(.textPrimary)

                        apiKeyField(provider: .anthropic, key: $anthropicKey)
                        apiKeyField(provider: .openai, key: $openaiKey)
                        apiKeyField(provider: .gemini, key: $geminiKey)

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

    @ViewBuilder
    private func apiKeyField(provider: AIProvider, key: Binding<String>) -> some View {
        let state = providerAuth.providerStates[provider] ?? .init()

        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 14))
                    .foregroundColor(.textPrimary)
                Text(provider.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                if state.isConnected {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text("Connected")
                    }
                    .font(Typography.badgeText)
                    .foregroundColor(.accentGreen)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 4)
                    .background(Color.accentGreen.opacity(0.2))
                    .cornerRadius(4)
                }
            }

            HStack(spacing: Spacing.md) {
                SecureField("Enter API key...", text: key)
                    .font(Typography.code)
                    .foregroundColor(.textPrimary)
                    .padding(Spacing.md)
                    .background(Color.fieldBg)
                    .cornerRadius(Spacing.radiusMd)
                    .overlay(RoundedRectangle(cornerRadius: Spacing.radiusMd).stroke(Color.fieldBorder, lineWidth: 1))

                Button(action: {
                    providerAuth.connectWithAPIKey(provider: provider, key: key.wrappedValue)
                    appState.refreshProviderStatuses()
                }) {
                    Text(state.isConnected ? "Connected" : "Connect")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(state.isConnected ? .accentGreen : .textPrimary)
                        .padding(.horizontal, Spacing.md)
                        .frame(height: Spacing.compactButtonHeight)
                        .background(state.isConnected ? Color.accentGreen.opacity(0.15) : Color.bgElevated)
                        .cornerRadius(Spacing.radiusSm)
                }
                .buttonStyle(.plain)
                .disabled(key.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private func loadCurrentValues() {
        guard let project = appState.currentProject else { return }
        projectName = project.name
        projectDescription = project.projectDescription
        projectType = ProjectType(rawValue: project.projectType) ?? .other
        defaultModel = project.defaultModel
        defaultProvider = project.defaultProvider
        githubRepo = project.githubRepo ?? ""
        selectedScreenSizes = Set(project.screenSizes)
        responsiveBehavior = project.responsiveBehavior
        techStack = project.techStack

        anthropicKey = KeychainService.shared.readAPIKey(for: .anthropic) ?? ""
        openaiKey = KeychainService.shared.readAPIKey(for: .openai) ?? ""
        geminiKey = KeychainService.shared.readAPIKey(for: .gemini) ?? ""
    }

    private func saveSettings() {
        let trimmedName = projectName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            showValidationError = true
            return
        }

        guard let project = appState.currentProject else { return }

        appState.projectService.updateProjectSettings(
            project,
            name: trimmedName,
            description: projectDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            projectType: projectType.rawValue,
            defaultModel: defaultModel,
            defaultProvider: defaultProvider,
            githubRepo: githubRepo.isEmpty ? nil : githubRepo,
            screenSizes: Array(selectedScreenSizes),
            responsiveBehavior: responsiveBehavior,
            techStack: techStack
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
