//
//  AuthStore.swift
//  Sunnyfi
//
//  10-digit access code sign-in. Matches the sunnyfi.co flow exactly:
//  the "10-digit code" is literally the password for a shared team
//  account (nik@sunnyfi.co). Standard Supabase email+password auth
//  under the hood — no edge function needed. The session persists in
//  Keychain so subsequent launches skip the sign-in screen.
//
//  See src/sunnyfi/lib/auth.ts in the web app for the canonical impl.
//

import Foundation
import Supabase

@MainActor
@Observable
final class AuthStore {
    enum State {
        case loading
        case signedOut
        case signedIn(email: String)
    }

    /// Shared team account. Anyone with a valid 10-digit code signs in as this user.
    private static let sharedLoginEmail = "nik@sunnyfi.co"

    var state: State = .loading
    var error: String?
    var isSigningIn: Bool = false

    private let client = SupabaseService.client
    private var stateTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func start() {
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            guard let self else { return }
            for await change in self.client.auth.authStateChanges {
                await self.apply(session: change.session)
            }
        }
    }

    private func apply(session: Session?) {
        if let s = session {
            self.state = .signedIn(email: s.user.email ?? "—")
        } else {
            self.state = .signedOut
        }
    }

    // MARK: - Sign in

    func signIn(code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 10, trimmed.allSatisfy(\.isNumber) else {
            self.error = "Enter the full 10-digit code."
            return
        }

        isSigningIn = true
        defer { isSigningIn = false }
        do {
            _ = try await client.auth.signIn(email: Self.sharedLoginEmail, password: trimmed)
            self.error = nil
            // authStateChanges will push .signedIn
        } catch {
            print("[AuthStore] sign-in error: \(String(describing: error))")
            self.error = Self.friendlyMessage(for: error)
        }
    }

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            print("[AuthStore] sign-out error: \(error)")
        }
    }

    // MARK: - Errors

    private static func friendlyMessage(for error: Error) -> String {
        let s = String(describing: error)
        if s.contains("Invalid login credentials") || s.contains("invalid_credentials") {
            return "Wrong code. Try again."
        }
        return error.localizedDescription
    }
}
