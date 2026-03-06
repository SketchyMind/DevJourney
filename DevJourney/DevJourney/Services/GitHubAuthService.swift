import Foundation
import AuthenticationServices
import Combine

@MainActor
final class GitHubAuthService: NSObject, ObservableObject {
    @Published var isAuthenticated = false
    @Published var username: String?
    @Published var avatarURL: String?
    @Published var isAuthenticating = false
    @Published var authError: String?

    // Users must register their own GitHub OAuth App and provide these.
    // For local dev, set via environment or Info.plist.
    private let clientId: String
    private let clientSecret: String
    private let callbackScheme = "devjourney"
    private let scopes = "repo,user"

    private let gitHubService = GitHubService()

    override init() {
        self.clientId = Bundle.main.object(forInfoDictionaryKey: "GITHUB_CLIENT_ID") as? String ?? ""
        self.clientSecret = Bundle.main.object(forInfoDictionaryKey: "GITHUB_CLIENT_SECRET") as? String ?? ""
        super.init()
        restoreSession()
    }

    // MARK: - Public API

    func startOAuth() {
        guard !clientId.isEmpty else {
            authError = "GitHub OAuth not configured. Add GITHUB_CLIENT_ID to Info.plist."
            return
        }

        isAuthenticating = true
        authError = nil

        let authURLString = "https://github.com/login/oauth/authorize"
            + "?client_id=\(clientId)"
            + "&redirect_uri=\(callbackScheme)://oauth/callback"
            + "&scope=\(scopes)"
            + "&state=\(UUID().uuidString)"

        guard let authURL = URL(string: authURLString) else {
            authError = "Failed to build auth URL"
            isAuthenticating = false
            return
        }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAuthenticating = false

                if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        return // User cancelled, not an error
                    }
                    self.authError = error.localizedDescription
                    return
                }

                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    self.authError = "No authorization code received"
                    return
                }

                await self.exchangeCodeForToken(code)
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    /// Authenticate using a Personal Access Token (classic or fine-grained).
    /// This is the simpler path that doesn't require a registered OAuth App.
    func authenticateWithPAT(_ token: String) async {
        isAuthenticating = true
        authError = nil

        do {
            let user = try await gitHubService.fetchAuthenticatedUser(token: token)
            try KeychainService.shared.saveGitHubToken(token)
            username = user.login
            avatarURL = user.avatarUrl
            isAuthenticated = true
        } catch {
            authError = "Invalid token: \(error.localizedDescription)"
        }
        isAuthenticating = false
    }

    func signOut() {
        try? KeychainService.shared.deleteGitHubToken()
        isAuthenticated = false
        username = nil
        avatarURL = nil
    }

    // MARK: - Private

    private func restoreSession() {
        guard let token = KeychainService.shared.readGitHubToken() else { return }
        Task {
            do {
                let user = try await gitHubService.fetchAuthenticatedUser(token: token)
                username = user.login
                avatarURL = user.avatarUrl
                isAuthenticated = true
            } catch {
                // Token expired or revoked
                try? KeychainService.shared.deleteGitHubToken()
            }
        }
    }

    private func exchangeCodeForToken(_ code: String) async {
        guard let url = URL(string: "https://github.com/login/oauth/access_token") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: String] = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "code": code
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                authError = "Token exchange failed"
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["access_token"] as? String
            else {
                authError = "No access token in response"
                return
            }

            try KeychainService.shared.saveGitHubToken(token)
            let user = try await gitHubService.fetchAuthenticatedUser(token: token)
            username = user.login
            avatarURL = user.avatarUrl
            isAuthenticated = true
        } catch {
            authError = "Authentication failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GitHubAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.mainWindow ?? ASPresentationAnchor()
    }
}
