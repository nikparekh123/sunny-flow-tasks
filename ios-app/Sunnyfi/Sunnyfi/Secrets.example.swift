//
//  Secrets.example.swift
//  Sunnyfi
//
//  TEMPLATE — the file below is wrapped in `#if false` so it never
//  reaches the compiler (synchronized folders compile every .swift,
//  so an active duplicate `enum Secrets` would error).
//
//  To set up a fresh checkout:
//    1. Copy this file to `Secrets.swift` (already gitignored)
//    2. In your copy: delete the `#if false` / `#endif` lines
//    3. Fill the real values from Supabase dashboard → Project Settings → API
//

#if false
import Foundation

enum Secrets {
    /// Supabase project URL — e.g. https://abcd1234.supabase.co
    static let supabaseURL = "https://your-project-ref.supabase.co"

    /// Supabase publishable (anon) key. Safe to ship in client builds —
    /// row-level security in Supabase is what guards data, not key secrecy.
    static let supabasePublishableKey = "sb_publishable_xxxxxxxxxxxxxxxxxxxxxxxxx"
}
#endif
