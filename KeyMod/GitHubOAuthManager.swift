//
//  GitHubOAuthManager.swift
//  KeyMod
//
//  Created on 2026/3/1.
//

import Foundation
import AuthenticationServices

/// Manages GitHub OAuth 2.0 authentication flow
class GitHubOAuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    
    static let shared = GitHubOAuthManager()
    
    // MARK: - Configuration
    // You need to register your app at https://github.com/settings/applications/new
    // OAuth App settings:
    // - Authorization callback URL: keymod://github-oauth-callback
    private let clientID = "Ov23liz3tlHVdy8OlBN3"
    private let clientSecret = "9f4cd0bb2f27c32ba33a6bcc0df00f28efdd4fd4"
    private let redirectURI = "keymod://github-oauth-callback"
    private let authorizeURL = "https://github.com/login/oauth/authorize"
    private let tokenURL = "https://github.com/login/oauth/access_token"
    
    // MARK: - Published state
    @Published var isAuthenticating = false
    @Published var authError: String?
    
    // MARK: - Private properties
    private let keychainKey = "GitHubOAuth.accessToken"
    private let usernameKeychainKey = "GitHubOAuth.username"
    private var authenticationSession: ASWebAuthenticationSession?
    private let logger = LogManager.shared
    
    // MARK: - Public computed properties
    
    var accessToken: String {
        get {
            KeychainHelper.shared.retrieve(key: keychainKey) ?? ""
        }
        set {
            if newValue.isEmpty {
                KeychainHelper.shared.delete(key: keychainKey)
            } else {
                KeychainHelper.shared.save(key: keychainKey, value: newValue)
            }
            objectWillChange.send()
        }
    }
    
    var username: String {
        get {
            KeychainHelper.shared.retrieve(key: usernameKeychainKey) ?? ""
        }
        set {
            if newValue.isEmpty {
                KeychainHelper.shared.delete(key: usernameKeychainKey)
            } else {
                KeychainHelper.shared.save(key: usernameKeychainKey, value: newValue)
            }
            objectWillChange.send()
        }
    }
    
    var isAuthenticated: Bool {
        !accessToken.isEmpty && !username.isEmpty
    }
    
    // MARK: - OAuth Flow
    
    func startLogin() {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: { $0.isKeyWindow }) else {
            authError = "Could not find active window"
            return
        }
        
        let state = generateRandomState()
        let scope = "repo workflow"
        
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/login/oauth/authorize"
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "allow_signup", value: "true")
        ]
        
        guard let authURL = components.url else {
            authError = "Could not build authentication URL"
            return
        }
        
        logger.log("Starting GitHub OAuth flow with URL: \(authURL.absoluteString)", category: "OAuth")
        isAuthenticating = true
        authError = nil
        
        authenticationSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "keymod"
        ) { [weak self] callbackURL, error in
            self?.handleAuthenticationCallback(callbackURL: callbackURL, error: error)
        }
        
        authenticationSession?.presentationContextProvider = self
        authenticationSession?.start()
    }
    
    private func handleAuthenticationCallback(callbackURL: URL?, error: Error?) {
        DispatchQueue.main.async {
            self.isAuthenticating = false
            
            if let error = error {
                let nsError = error as NSError
                // ASWebAuthenticationSessionError.cancelledLogin = 1
                if nsError.code == 1 {
                    self.logger.log("User cancelled GitHub login", category: "OAuth")
                } else {
                    self.logger.log("GitHub authentication error: \(error.localizedDescription)", category: "OAuth", level: .error)
                    self.authError = "Authentication failed: \(error.localizedDescription)"
                }
                return
            }
            
            guard let callbackURL = callbackURL else {
                self.authError = "No callback URL received"
                return
            }
            
            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let queryItems = components.queryItems else {
                self.authError = "Invalid callback URL"
                return
            }
            
            // Check for errors from GitHub
            if let errorParam = queryItems.first(where: { $0.name == "error" })?.value {
                let errorDesc = queryItems.first(where: { $0.name == "error_description" })?.value ?? errorParam
                self.logger.log("GitHub returned error: \(errorDesc)", category: "OAuth", level: .error)
                self.authError = "GitHub error: \(errorDesc)"
                return
            }
            
            guard let authCode = queryItems.first(where: { $0.name == "code" })?.value else {
                self.authError = "No authorization code received"
                return
            }
            
            self.logger.log("Received authorization code from GitHub", category: "OAuth")
            self.exchangeCodeForToken(code: authCode)
        }
    }
    
    private func exchangeCodeForToken(code: String) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/login/oauth/access_token"
        
        let body = "client_id=\(clientID)&client_secret=\(clientSecret)&code=\(code)&redirect_uri=\(redirectURI)"
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body.data(using: .utf8)
        
        logger.log("Exchanging authorization code for access token", category: "OAuth")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.logger.log("Token exchange network error: \(error.localizedDescription)", category: "OAuth", level: .error)
                    self.authError = "Network error: \(error.localizedDescription)"
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.authError = "No response from token endpoint"
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let error = json["error"] as? String {
                        DispatchQueue.main.async {
                            self.logger.log("GitHub token error: \(error)", category: "OAuth", level: .error)
                            self.authError = "Token error: \(error)"
                        }
                        return
                    }
                    
                    if let accessToken = json["access_token"] as? String {
                        self.logger.log("✅ Successfully obtained access token from GitHub", category: "OAuth")
                        self.accessToken = accessToken
                        
                        // Fetch user profile to get username
                        self.fetchUserProfile()
                    } else {
                        DispatchQueue.main.async {
                            self.authError = "No access token in response"
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.logger.log("Failed to parse token response: \(error.localizedDescription)", category: "OAuth", level: .error)
                    self.authError = "Failed to parse response"
                }
            }
        }.resume()
    }
    
    private func fetchUserProfile() {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.log("Failed to fetch user profile: \(error.localizedDescription)", category: "OAuth", level: .error)
                return
            }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let login = json["login"] as? String else {
                self.logger.log("Could not extract login from user profile", category: "OAuth", level: .warning)
                return
            }
            
            DispatchQueue.main.async {
                self.username = login
                self.logger.log("✅ Authenticated as: \(login)", category: "OAuth")
            }
        }.resume()
    }
    
    func logout() {
        accessToken = ""
        username = ""
        authError = nil
        logger.log("Logged out from GitHub", category: "OAuth")
    }
    
    // MARK: - Helpers
    
    private func generateRandomState() -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<32).map { _ in letters.randomElement()! })
    }
    
    // MARK: - ASWebAuthenticationPresentationContextProviding
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: { $0.isKeyWindow }) else {
            return ASPresentationAnchor()
        }
        return window
    }
}
