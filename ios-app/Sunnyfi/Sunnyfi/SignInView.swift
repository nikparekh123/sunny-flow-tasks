//
//  SignInView.swift
//  Sunnyfi
//
//  Single-field 10-digit access code sign-in — matches sunnyfi.co.
//  No email, no OTP. Type the code, tap Sign in. The session persists
//  in Keychain so subsequent launches skip this screen.
//

import SwiftUI

struct SignInView: View {
    let auth: AuthStore

    @State private var code: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 6) {
                Text("Sunnyfi")
                    .font(.ui(size: 36, weight: .bold))
                    .foregroundStyle(Color.theme.neon)
                Text("Enter your 10-digit access code")
                    .font(.ui(size: 13))
                    .foregroundStyle(Color.theme.fg3)
            }

            TextField("", text: $code, prompt: Text("10-digit code").foregroundStyle(Color.theme.fg3))
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .font(.numeric(size: 22, weight: .medium))
                .foregroundStyle(Color.theme.fg1)
                .multilineTextAlignment(.center)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(Color.theme.cardSolid)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg)
                                .strokeBorder(Color.theme.soft, lineWidth: 0.5)
                        )
                )
                .padding(.horizontal, 24)
                .padding(.top, 12)

            if let err = auth.error {
                Text(err)
                    .font(.ui(size: 12))
                    .foregroundStyle(Color.theme.neg)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                Task { await auth.signIn(code: code) }
            } label: {
                ZStack {
                    Capsule().fill(Color.theme.neon)
                    if auth.isSigningIn {
                        ProgressView().tint(.black)
                    } else {
                        Text("Sign in")
                            .font(.ui(size: 16, weight: .bold))
                            .foregroundStyle(Color.black)
                    }
                }
                .frame(height: 48)
            }
            .disabled(code.count != 10 || auth.isSigningIn)
            .opacity(code.count != 10 ? 0.5 : 1)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .background(Color.theme.page.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
