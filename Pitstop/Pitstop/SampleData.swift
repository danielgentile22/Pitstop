//
//  SampleData.swift
//  Pitstop
//
//  Local seeding is disabled. The Supabase database is the source of truth
//  and delivers sample bathrooms to every user via the regular sync path.
//
//  seedIfNeeded() is kept as an intentional no-op so the call site in
//  PitstopApp (if any) can remain without needing a code change.
//

import SwiftData

enum SampleData {

    /// No-op. Sample data lives in the Supabase database and is downloaded
    /// on first sync — not seeded locally.
    static func seedIfNeeded(in context: ModelContext) {
        _ = context
    }
}
