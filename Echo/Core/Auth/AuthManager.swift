import Foundation
import Supabase
import Observation

@Observable
final class AuthManager {
    enum State {
        case loading
        case signedOut
        case signedIn(userId: UUID, email: String?)
    }

    private(set) var state: State = .loading
    private var authStateTask: Task<Void, Never>?

    init() {
        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in SupabaseService.client.auth.authStateChanges {
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                    if let session {
                        self.state = .signedIn(userId: session.user.id, email: session.user.email)
                    } else {
                        self.state = .signedOut
                    }
                case .signedOut:
                    self.state = .signedOut
                default:
                    break
                }
            }
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    func signIn(email: String, password: String) async throws {
        try await SupabaseService.client.auth.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        try await SupabaseService.client.auth.signUp(email: email, password: password)
    }

    func signOut() async throws {
        try await SupabaseService.client.auth.signOut()
    }

    /// The current session's access token, needed for calling our authenticated API routes.
    func currentAccessToken() async throws -> String {
        let session = try await SupabaseService.client.auth.session
        return session.accessToken
    }
}
