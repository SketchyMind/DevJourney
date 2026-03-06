import Foundation
import AuthenticationServices
import Combine

/// Manages OAuth 2.0 authentication for AI providers (OpenAI, Google/Gemini).
/// Anthropic uses API key auth only per their docs.
@MainActor
final class AIProviderAuthService: NSObject, ObservableObject {
    @Published var providerStates: [AIProvider: ProviderAuthState] = [
        .anthropic: .init(),
        .openai: .init(),
        .gemini: .init()
    ]
    @Published var isAuthenticating: AIProvider?

    struct ProviderAuthState {
        var isConnected = false
        var authMethod: AuthMethod = .none
        var error: String?

        enum AuthMethod {
            case none, apiKey, oauth
        }
    }

    // OAuth client IDs loaded from Info.plist
    private let openaiClientId: String
    private let openaiClientSecret: String
    private let googleClientId: String
    private let googleClientSecret: String
    private let callbackScheme = "devjourney"

    override init() {
        self.openaiClientId = Bundle.main.object(forInfoDictionaryKey: "OPENAI_CLIENT_ID") as? String ?? ""
        self.openaiClientSecret = Bundle.main.object(forInfoDictionaryKey: "OPENAI_CLIENT_SECRET") as? String ?? ""
        self.googleClientId = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_ID") as? String ?? ""
        self.googleClientSecret = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_CLIENT_SECRET") as? String ?? ""
        super.init()
        restoreAllSessions()
    }

    // MARK: - Public API

    /// Connect a provider via API key (works for all providers).
    func connectWithAPIKey(provider: AIProvider, key: String) {
        let trimmedKey = key.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else { return }
        try? KeychainService.shared.saveAPIKey(for: provider, key: trimmedKey)
        providerStates[provider]?.isConnected = true
        providerStates[provider]?.authMethod = .apiKey
        providerStates[provider]?.error = nil
    }

    /// Start OAuth flow for OpenAI.
    func startOpenAIOAuth() {
        guard !openaiClientId.isEmpty else {
            providerStates[.openai]?.error = "OpenAI OAuth not configured. Add OPENAI_CLIENT_ID to Info.plist, or use an API key."
            return
        }

        isAuthenticating = .openai
        providerStates[.openai]?.error = nil

        // OpenAI OAuth 2.0 authorization endpoint
        let authURLString = "https://auth.openai.com/authorize"
            + "?client_id=\(openaiClientId)"
            + "&redirect_uri=\(callbackScheme)://oauth/openai"
            + "&response_type=code"
            + "&scope=openai.public"
            + "&state=\(UUID().uuidString)"

        guard let authURL = URL(string: authURLString) else {
            providerStates[.openai]?.error = "Failed to build auth URL"
            isAuthenticating = nil
            return
        }

        startWebAuthSession(url: authURL, provider: .openai, callbackPath: "openai")
    }

    /// Start OAuth flow for Google (Gemini).
    func startGoogleOAuth() {
        guard !googleClientId.isEmpty else {
            providerStates[.gemini]?.error = "Google OAuth not configured. Add GOOGLE_CLIENT_ID to Info.plist, or use an API key."
            return
        }

        isAuthenticating = .gemini
        providerStates[.gemini]?.error = nil

        // Google OAuth 2.0 authorization endpoint
        let scopes = "https://www.googleapis.com/auth/cloud-platform https://www.googleapis.com/auth/generative-language.retriever"
        let encodedScopes = scopes.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? scopes

        let authURLString = "https://accounts.google.com/o/oauth2/v2/auth"
            + "?client_id=\(googleClientId)"
            + "&redirect_uri=\(callbackScheme)://oauth/google"
            + "&response_type=code"
            + "&scope=\(encodedScopes)"
            + "&access_type=offline"
            + "&prompt=consent"
            + "&state=\(UUID().uuidString)"

        guard let authURL = URL(string: authURLString) else {
            providerStates[.gemini]?.error = "Failed to build auth URL"
            isAuthenticating = nil
            return
        }

        startWebAuthSession(url: authURL, provider: .gemini, callbackPath: "google")
    }

    /// Disconnect a provider (removes stored credentials).
    func disconnect(provider: AIProvider) {
        try? KeychainService.shared.deleteAPIKey(for: provider)
        // Also remove OAuth token if stored separately
        try? KeychainService.shared.delete(service: oauthTokenService(provider))
        providerStates[provider] = .init()
    }

    /// Check if a provider supports OAuth (vs API key only).
    func supportsOAuth(_ provider: AIProvider) -> Bool {
        switch provider {
        case .anthropic: return false  // Anthropic prohibits OAuth for third-party apps
        case .openai: return !openaiClientId.isEmpty
        case .gemini: return !googleClientId.isEmpty
        }
    }

    // MARK: - Private

    private func restoreAllSessions() {
        for provider in AIProvider.allCases {
            let hasAPIKey = KeychainService.shared.isProviderConnected(provider)
            let hasOAuthToken = KeychainService.shared.exists(service: oauthTokenService(provider))

            if hasOAuthToken {
                providerStates[provider]?.isConnected = true
                providerStates[provider]?.authMethod = .oauth
            } else if hasAPIKey {
                providerStates[provider]?.isConnected = true
                providerStates[provider]?.authMethod = .apiKey
            }
        }
    }

    private func oauthTokenService(_ provider: AIProvider) -> String {
        "com.devjourney.oauth.\(provider.rawValue)"
    }

    private func startWebAuthSession(url: URL, provider: AIProvider, callbackPath: String) {
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAuthenticating = nil

                if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        return
                    }
                    self.providerStates[provider]?.error = error.localizedDescription
                    return
                }

                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    self.providerStates[provider]?.error = "No authorization code received"
                    return
                }

                await self.exchangeCode(code, for: provider)
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }

    private func exchangeCode(_ code: String, for provider: AIProvider) async {
        let tokenURL: String
        let body: [String: String]

        switch provider {
        case .openai:
            tokenURL = "https://auth.openai.com/token"
            body = [
                "grant_type": "authorization_code",
                "client_id": openaiClientId,
                "client_secret": openaiClientSecret,
                "code": code,
                "redirect_uri": "\(callbackScheme)://oauth/openai"
            ]
        case .gemini:
            tokenURL = "https://oauth2.googleapis.com/token"
            body = [
                "grant_type": "authorization_code",
                "client_id": googleClientId,
                "client_secret": googleClientSecret,
                "code": code,
                "redirect_uri": "\(callbackScheme)://oauth/google"
            ]
        case .anthropic:
            return // Anthropic doesn't support OAuth
        }

        guard let url = URL(string: tokenURL) else {
            providerStates[provider]?.error = "Invalid token URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let bodyString = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                providerStates[provider]?.error = "Token exchange failed: \(errorBody)"
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String
            else {
                providerStates[provider]?.error = "No access token in response"
                return
            }

            // Store the OAuth access token
            try KeychainService.shared.saveString(service: oauthTokenService(provider), value: accessToken)

            // Also store as API key so the AI client can use it
            try KeychainService.shared.saveAPIKey(for: provider, key: accessToken)

            providerStates[provider]?.isConnected = true
            providerStates[provider]?.authMethod = .oauth
            providerStates[provider]?.error = nil

        } catch {
            providerStates[provider]?.error = "Authentication failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension AIProviderAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.mainWindow ?? ASPresentationAnchor()
    }
}
