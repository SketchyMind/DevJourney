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
    @State private var githubEnabled: Bool = KeychainService.shared.readGitHubToken() != nil
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

    private var recentProjects: [Project] {
        appState.recentProjects()
    }

    var isFormValid: Bool {
        !selectedFolderPath.isEmpty
    }

    var body: some View {
        if isInSetup, let project = createdProject {
            ProjectSetupView(
                project: project,
                onComplete: {
                    appState.selectProject(project)
                    isInSetup = false
                },
                onSkip: {
                    appState.selectProject(project)
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
                            if !recentProjects.isEmpty {
                                recentProjectsSection
                            }

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

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Recent Workspaces")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Spacer()

                Text("Last \(recentProjects.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textMuted)
            }

            VStack(spacing: Spacing.sm) {
                ForEach(recentProjects, id: \.id) { project in
                    Button {
                        appState.selectProject(project)
                    } label: {
                        HStack(spacing: Spacing.md) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.accentPurple.opacity(0.14))
                                    .frame(width: 40, height: 40)
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.accentPurple)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(1)

                                Text(project.folderPath)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundColor(.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(stageStatusLabel(for: project))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.accentGreen)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentGreen.opacity(0.08))
                                .cornerRadius(999)
                        }
                        .padding(Spacing.md)
                        .background(Color.bgElevated)
                        .cornerRadius(Spacing.radiusMd)
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.radiusMd)
                                .stroke(Color.borderSubtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

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

                    Button {
                        gitHubAuth.signOut()
                    } label: {
                        Text("Sign Out")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accentRed)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.accentRed.opacity(0.1))
                            .cornerRadius(100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 100)
                                    .stroke(Color.accentRed.opacity(0.3), lineWidth: 1)
                            )
                    }
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
                // Not authenticated - show PAT auth
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // Generate token button
                    Button {
                        if let url = URL(string: "https://github.com/settings/tokens/new?scopes=repo,user&description=DevJourney") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 13, weight: .medium))
                            Text("Generate Token on GitHub")
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

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.accentYellow)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Generate a token, then paste it below.")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.textSecondary)
                            Text("Enable scopes: ")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.textSecondary)
                            + Text("repo")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.accentYellow)
                            + Text(" and ")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(.textSecondary)
                            + Text("user")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.accentYellow)
                        }
                    }
                    .padding(Spacing.sm)
                    .background(Color.accentYellow.opacity(0.08))
                    .cornerRadius(Spacing.radiusSm)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.radiusSm)
                            .stroke(Color.accentYellow.opacity(0.25), lineWidth: 1)
                    )

                    // PAT input
                    VStack(alignment: .leading, spacing: Spacing.gapXs) {
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
        panel.canCreateDirectories = true
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
            if let existingProject = appState.projectService.loadOrImportProject(folderPath: selectedFolderPath) {
                createdProject = existingProject
                isCreating = false
                isInSetup = true
                return
            }

            try initializeGitRepositoryIfNeeded(at: URL(fileURLWithPath: selectedFolderPath))

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
            appState.projectService.ensureDefaultProviderConfigs(for: project)

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

    private func stageStatusLabel(for project: Project) -> String {
        let ticketCount = appState.projectService.getProjectTickets(projectId: project.id).count
        if ticketCount == 0 {
            return "No tickets"
        }
        if ticketCount == 1 {
            return "1 ticket"
        }
        return "\(ticketCount) tickets"
    }

    private func initializeGitRepositoryIfNeeded(at folderURL: URL) throws {
        let gitFolderURL = folderURL.appendingPathComponent(".git", isDirectory: true)
        if FileManager.default.fileExists(atPath: gitFolderURL.path) {
            return
        }

        let task = Process()
        let outputPipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["init"]
        task.currentDirectoryURL = folderURL
        task.standardOutput = outputPipe
        task.standardError = outputPipe
        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "DevJourney.GitInit",
                code: Int(task.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: output?.isEmpty == false
                        ? output!
                        : "Failed to initialize a Git repository in the selected folder."
                ]
            )
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
            let git = GitHubService()
            let projectURL = URL(fileURLWithPath: selectedFolderPath)

            // Ensure there's at least a .gitignore so we have something to commit
            let gitignorePath = projectURL.appendingPathComponent(".gitignore")
            if !FileManager.default.fileExists(atPath: gitignorePath.path) {
                try? ".DS_Store\n.build/\n*.xcuserstate\n".write(to: gitignorePath, atomically: true, encoding: .utf8)
            }

            // Use token-embedded HTTPS URL so git push can authenticate
            let authedURL = "https://x-access-token:\(token)@github.com/\(response.fullName).git"

            // Reuse origin when the selected folder is already a repository.
            let existingOrigin = await git.runGitAsync(at: projectURL, args: ["remote", "get-url", "origin"])
            if existingOrigin?.isEmpty == false {
                _ = await git.runGitAsync(at: projectURL, args: ["remote", "set-url", "origin", authedURL])
            } else {
                _ = await git.runGitAsync(at: projectURL, args: ["remote", "add", "origin", authedURL])
            }

            // Create initial commit and push
            _ = await git.runGitAsync(at: projectURL, args: ["add", "-A"])
            _ = await git.runGitAsync(at: projectURL, args: [
                "-c", "user.name=\(gitHubAuth.username ?? "DevJourney")",
                "-c", "user.email=\(gitHubAuth.username ?? "devjourney")@users.noreply.github.com",
                "commit", "-m", "Initial commit"
            ])
            _ = await git.runGitAsync(at: projectURL, args: ["branch", "-M", "main"])
            _ = await git.runGitAsync(at: projectURL, args: ["push", "-u", "origin", "main"])

            // Replace remote URL with clean one (don't store token in git config)
            _ = await git.runGitAsync(at: projectURL, args: ["remote", "set-url", "origin", response.cloneUrl])

            project.githubRepo = response.htmlUrl
            print("GitHub repo created and initial push completed: \(response.htmlUrl)")
        } catch {
            // Repo creation failed - not critical, user can retry from settings
            print("GitHub repo creation failed: \(error)")
        }
    }
}
