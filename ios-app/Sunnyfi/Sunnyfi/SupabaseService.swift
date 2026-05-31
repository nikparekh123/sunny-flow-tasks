//
//  SupabaseService.swift
//  Sunnyfi
//
//  Thin wrapper around the Supabase Swift SDK. Holds the singleton client
//  and exposes typed query helpers used by PortfolioStore.
//
//  Add the package once via Xcode:
//    File → Add Package Dependencies →
//      https://github.com/supabase/supabase-swift  (use latest tag)
//    Add product `Supabase` to the Sunnyfi target.
//

import Foundation
import Supabase

@MainActor
enum SupabaseService {
    static let client: SupabaseClient = {
        guard let url = URL(string: Secrets.supabaseURL) else {
            fatalError("Invalid Supabase URL in Secrets.swift")
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: Secrets.supabasePublishableKey)
    }()
}
