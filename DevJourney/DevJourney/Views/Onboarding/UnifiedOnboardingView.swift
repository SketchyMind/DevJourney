import SwiftUI
import SwiftData
import AppKit

struct UnifiedOnboardingView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @StateObject private var gitHubAuth = GitHubAuthService()

    @State private var selectedFolderPath: String = ""
    @State private var projectDescription: String = ""
    @State private var projectType: ProjectType = .webApp
    @State private var githubEnabled: Bool = false
    @State private var createNewRepo: Bool = true
    @State private var repoName: String = "devjourney-project"
    @State private var existingRepoURL: String = ""
    @State private var repoVisibility: RepoVisibility = .privateRepo
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var isInSetup: Bool = false
    @State private var createdProject: Project?
    @State private var patInput: String = ""

    enum RepoVisibility: String {
        case privateRepo = "Private"
        case publicRepo = "Public"
    }

    private var projectName: String {
        URL(fileURLWithPath: selectedFolderPath).lastPathComponent
    }

    var isFormValid: Bool {
        !selectedFolderPath.isEmpty
    }

    var body: some View {
        if isInSetup, let project = createdProject {
            ProjectSetupView(
                project: project,
                onComplete: {
                    appState.currentProject = project
                    isInSetup = false
                },
                onSkip: {
                    appState.currentProject = project
                    isInSetup = false
                }
            )
            .environmentObject(appState)
        } else {
            ZStack {
                Color.bgApp.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Branded header
                    VStack(spacing: Spacing.sm) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.accentPurple)

                        Text("Welcome to DevJourney")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.textPrimary)

                        Text("Select a folder \u{2013} its name becomes your project name")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.top, Spacing.xxl)
                    .padding(.bottom, Spacing.xxl)

                    // Main content card
                    ScrollView {
                        VStack(spacing: Spacing.xl) {
                            // Workspace Folder Section
                            workspaceFolderSection

                            // Project Description Section
                            descriptionSection

                            // GitHub Section
                            githubSection
                        }
                        .padding(Spacing.xl)
                        .background(Color.bgSurface)
                        .cornerRadius(Spacing.radiusLg)
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.radiusLg)
                                .stroke(Color.borderSubtle, lineWidth: 1)
                        )
                    }
                    .frame(maxWidth: 500)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.xl)

                    // Continue button
                    Button(action: createProject) {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.bgApp)
                            .frame(maxWidth: 500)
                            .frame(height: 44)
                            .background(Color.accentPurple)
                            .cornerRadius(Spacing.radiusMd)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isFormValid)
                    .opacity(isFormValid ? 1.0 : 0.5)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.xl)
                }

                // Loading overlay
                if isCreating {
                    ZStack {
                        Color.black.opacity(0.5).ignoresSafeArea()
                        VStack(spacing: Spacing.lg) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.accentPurple)
                            Text("Creating project...")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.textPrimary)
                        }
                        .padding(Spacing.xl)
                        .background(Color.bgSurface)
                        .cornerRadius(Spacing.radiusLg)
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { showError = false }
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: selectedFolderPath) { _, newPath in
                repoName = URL(fileURLWithPath: newPath).lastPathComponent
            }
        }
    }

    // MARK: - Sections

    private var workspaceFolderSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Workspace Folder")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)

            HStack(spacing: Spacing.md) {
                Image(systemName: "folder")
                    .foregroundColor(.textSecondary)

                Text(selectedFolderPath.isEmpty ? "/Users/user/workspace..." : selectedFolderPath)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)

                Spacer()

                Button(action: selectFolder) {
                    Text("Browse")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentPurple)
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.md)
            .background(Color.bgElevated)
            .cornerRadius(Spacing.radiusMd)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusMd)
                    .stroke(Color.borderSubtle, lineWidth: 1)
            )
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Description (Optional)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)

            TextEditor(text: $projectDescription)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(Spacing.sm)
                .background(Color.bgElevated)
                .cornerRadius(Spacing.radiusMd)
                .overlay(
                    RoundedRectangle(cornerRadius: Spacing.radiusMd)
                        .stroke(Color.borderSubtle, lineWidth: 1)
                )
        }
    }

    private var githubSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.gapXs) {
                    Text("Connect to GitHub")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("Optional \u{2013} sync your project with a repository")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                Toggle("", isOn: $githubEnabled)
                    .tint(.accentPurple)
            }

            if githubEnabled {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Auth status
                    githubAuthSection

                    if gitHubAuth.isAuthenticated {
                        // Repository options
                        Text("Repository")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textPrimary)

                        createNewRepoOption
                        connectExistingRepoOption

                        // Visibility (only for create new)
                        if createNewRepo {
                            visibilityPicker
                        }
                    }

                    // Info text
                    HStack(spacing: Spacing.gapXs) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.textMuted)

                        Text("DevJourney will automatically commit changes as the agent works. You can review diffs before pushing to remote.")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.textMuted)
                    }
                }
            }
        }
    }

    // MARK: - GitHub Auth

    private var githubAuthSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if gitHubAuth.isAuthenticated {
                // Authenticated state
                HStack(spacing: Spacing.gapSm) {
                    Circle()
                        .fill(Color.accentGreen)
                        .frame(width: 8, height: 8)

                    Text("Authenticated as \(gitHubAuth.username ?? "unknown")")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.textSecondary)

                    Text("Connected")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.accentGreen.opacity(0.1))
                        .cornerRadius(4)

                    Spacer()

                    Button("Sign Out") {
                        gitHubAuth.signOut()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textMuted)
                    .buttonStyle(.plain)
                }
            } else if gitHubAuth.isAuthenticating {
                HStack(spacing: Spacing.gapSm) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Authenticating...")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.textSecondary)
                }
            } else {
                // Not authenticated - show options
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // OAuth button
                    Button(action: { gitHubAuth.startOAuth() }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 13, weight: .medium))
                            Text("Sign in with GitHub")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Color.bgElevated)
                        .cornerRadius(Spacing.radiusMd)
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.radiusMd)
                                .stroke(Color.borderSubtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    // Divider
                    HStack {
                        Rectangle().fill(Color.borderSubtle).frame(height: 1)
                        Text("or")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.textMuted)
                        Rectangle().fill(Color.borderSubtle).frame(height: 1)
                    }

                    // PAT input
                    VStack(alignment: .leading, spacing: Spacing.gapXs) {
                        Text("Personal Access Token")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textSecondary)
                        HStack(spacing: Spacing.gapSm) {
                            SecureField("ghp_...", text: $patInput)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundColor(.textPrimary)
                                .padding(Spacing.sm)
                                .background(Color.bgElevated)
                                .cornerRadius(Spacing.radiusSm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Spacing.radiusSm)
                                        .stroke(Color.borderSubtle, lineWidth: 1)
                                )
                            Button("Connect") {
                                Task {
                                    await gitHubAuth.authenticateWithPAT(patInput)
                                    if gitHubAuth.isAuthenticated {
                                        patInput = ""
                                    }
                                }
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.accentPurple)
                            .buttonStyle(.plain)
                            .disabled(patInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }

                if let error = gitHubAuth.authError {
                    Text(error)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.accentRed)
                }
            }
        }
    }

    // MARK: - Repo Options

    private var createNewRepoOption: some View {
        Button(action: { createNewRepo = true }) {
            VStack(alignment: .leading, spacing: Spacing.gapSm) {
                HStack(spacing: Spacing.gapSm) {
                    Image(systemName: createNewRepo ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(createNewRepo ? .accentPurple : .textMuted)

                    Text("Create new repository")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                }

                if createNewRepo {
                    Text("A new GitHub repository will be created for this project")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.textSecondary)
                        .padding(.leading, 22)

                    HStack(spacing: Spacing.gapXs) {
                        Text("\(gitHubAuth.username ?? "user") /")
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.textSecondary)

                        TextField("repo-name", text: $repoName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundColor(.textPrimary)
                    }
                    .padding(.leading, 22)
                }
            }
            .padding(Spacing.md)
            .background(createNewRepo ? Color.accentPurple.opacity(0.1) : Color.bgElevated)
            .cornerRadius(Spacing.radiusMd)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusMd)
                    .stroke(createNewRepo ? Color.accentPurple : Color.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var connectExistingRepoOption: some View {
        Button(action: { createNewRepo = false }) {
            VStack(alignment: .leading, spacing: Spacing.gapSm) {
                HStack(spacing: Spacing.gapSm) {
                    Image(systemName: !createNewRepo ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(!createNewRepo ? .accentPurple : .textMuted)

                    VStack(alignment: .leading, spacing: Spacing.gapXs) {
                        Text("Connect existing repository")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text("Link to a repository you already have on GitHub")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.textSecondary)
                    }
                }

                if !createNewRepo {
                    TextField("https://github.com/user/repo", text: $existingRepoURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(.textPrimary)
                        .padding(Spacing.sm)
                        .background(Color.bgApp)
                        .cornerRadius(Spacing.radiusSm)
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.radiusSm)
                                .stroke(Color.borderSubtle, lineWidth: 1)
                        )
                        .padding(.leading, 22)
                }
            }
            .padding(Spacing.md)
            .background(!createNewRepo ? Color.accentPurple.opacity(0.1) : Color.bgElevated)
            .cornerRadius(Spacing.radiusMd)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.radiusMd)
                    .stroke(!createNewRepo ? Color.accentPurple : Color.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var visibilityPicker: some View {
        HStack(spacing: Spacing.gapMd) {
            Text("Visibility:")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textPrimary)

            Button(action: { repoVisibility = .privateRepo }) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                    Text("Private")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(repoVisibility == .privateRepo ? .accentPurple : .textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(repoVisibility == .privateRepo ? Color.accentPurple.opacity(0.1) : Color.clear)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(repoVisibility == .privateRepo ? Color.accentPurple : Color.borderSubtle, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button(action: { repoVisibility = .publicRepo }) {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                    Text("Public")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(repoVisibility == .publicRepo ? .accentPurple : .textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(repoVisibility == .publicRepo ? Color.accentPurple.opacity(0.1) : Color.clear)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(repoVisibility == .publicRepo ? Color.accentPurple : Color.borderSubtle, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Actions

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your project folder"
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let path = url.path
        let fm = FileManager.default
        var isDir: ObjCBool = false

        guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return }
        selectedFolderPath = path
    }

    private func createProject() {
        guard !selectedFolderPath.isEmpty else {
            errorMessage = "Please select a project folder"
            showError = true
            return
        }

        isCreating = true

        do {
            // Initialize git repository in project folder
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            task.arguments = ["init"]
            task.currentDirectoryURL = URL(fileURLWithPath: selectedFolderPath)
            try task.run()
            task.waitUntilExit()

            // Determine GitHub repo URL
            var githubRepo: String?
            if githubEnabled && gitHubAuth.isAuthenticated {
                if createNewRepo {
                    githubRepo = "https://github.com/\(gitHubAuth.username ?? "user")/\(repoName)"
                } else if !existingRepoURL.isEmpty {
                    githubRepo = existingRepoURL
                }
            }

            // Create project record
            let project = Project(
                name: projectName,
                projectDescription: projectDescription,
                projectType: projectType.rawValue,
                folderPath: selectedFolderPath,
                githubRepo: githubRepo,
                githubUsername: gitHubAuth.username,
                githubAvatarURL: gitHubAuth.avatarURL,
                repoVisibility: repoVisibility == .privateRepo ? "private" : "public",
                repoCreationMode: createNewRepo ? "create" : "connect"
            )

            modelContext.insert(project)
            try modelContext.save()

            // If creating a new repo, do it asynchronously
            if githubEnabled && gitHubAuth.isAuthenticated && createNewRepo {
                Task {
                    await createGitHubRepo(for: project)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                createdProject = project
                isCreating = false
                isInSetup = true
            }
        } catch {
            isCreating = false
            errorMessage = "Failed to create project: \(error.localizedDescription)"
            showError = true
        }
    }

    private func createGitHubRepo(for project: Project) async {
        guard let token = KeychainService.shared.readGitHubToken() else { return }

        let request = GitHubCreateRepoRequest(
            name: repoName,
            description: projectDescription,
            private: repoVisibility == .privateRepo,
            autoInit: false
        )

        do {
            let response = try await GitHubService().createRepository(request: request, token: token)
            // Add remote to local git repo
            let projectURL = URL(fileURLWithPath: selectedFolderPath)
            _ = await GitHubService().runGitAsync(at: projectURL, args: ["remote", "add", "origin", response.cloneUrl])
            project.githubRepo = response.htmlUrl
        } catch {
            // Repo creation failed - not critical, user can retry from settings
            print("GitHub repo creation failed: \(error)")
        }
    }
}
