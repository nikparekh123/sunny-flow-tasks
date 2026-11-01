//
//  AuthStore.swift
//  Sunny (carried over from the Sunnyfi app unchanged, handoff 18)
//
//  10-digit access code sign-in. Matches the sunnyfi.co flow exactly:
//  the "10-digit code" is literally the password for a shared team
//  account (nik@sunnyfi.co). Standard Supabase email+password auth
//  under the hood — no edge function needed. The session persists in
//  Keychain so subsequent launches skip the sign-in screen.
//  Since 31 Oct 2026 a second code opens book N's login (the cousin's).
//
//  See src/sunnyfi/lib/auth.ts in the web app for the canonical impl.
//

import Foundation
import Supabase

@MainActor
@Observable
final class AuthStore {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(email: String)
    }

    /// Shared team account. Anyone with a valid 10-digit code signs in as this user.
    private static let sharedLoginEmail = "nik@sunnyfi.co"
    /// Book N's login (31 Oct 2026): the cousin's own 10-digit code, on the same
    /// screen. A viewer of book N only, so it never opens book S. A code is tried
    /// here when it is not book S's; the database refuses the same code for both.
    private static let bookNLoginEmail = "book-n@sunnyfi.co"

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
                self.apply(session: change.session)
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
        var last: Error?
        for email in [Self.sharedLoginEmail, Self.bookNLoginEmail] {
            do {
                _ = try await client.auth.signIn(email: email, password: trimmed)
                self.error = nil
                // authStateChanges will push .signedIn
                return
            } catch {
                print("[AuthStore] sign-in error: \(String(describing: error))")
                last = error
                // Only a wrong code moves on to the next login; no network stops here.
                guard Self.isWrongCode(error) else { break }
            }
        }
        if let last { self.error = Self.friendlyMessage(for: last) }
    }

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            print("[AuthStore] sign-out error: \(error)")
        }
        // The Ink rebuild keeps no on-disk portfolio cache (NvdaStore is
        // memory-only), so there's nothing to clear on sign-out.
    }

    // MARK: - Errors

    private static func isWrongCode(_ error: Error) -> Bool {
        let s = String(describing: error)
        return s.contains("Invalid login credentials") || s.contains("invalid_credentials")
    }

    private static func friendlyMessage(for error: Error) -> String {
        if isWrongCode(error) { return "Wrong code. Try again." }
        return error.localizedDescription
    }
}
