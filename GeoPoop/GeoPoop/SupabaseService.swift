//
//  SupabaseService.swift
//  GeoPoop
//
//  @Observable singleton that owns every interaction with Supabase:
//    • Auth    — email/password sign-in, sign-up, sign-out, forgot password
//    • Profile — fetch and update the user's display name
//    • Sync    — download accessible bathrooms → upsert into SwiftData (delta)
//    • Push    — upsert / delete a single bathroom to/from Supabase
//    • Photos  — upload/download/delete files in Supabase Storage
//    • Verify  — increment community verification count on a bathroom
//    • Report  — submit a moderation report for a bathroom
//    • Emergency — direct cloud query for the nearest bathroom
//
//  ── Sync Strategy ─────────────────────────────────────────────────────────
//
//  Delta sync: on every syncAll(), the last successful sync timestamp is
//  loaded from UserDefaults (keyed per user ID). The query includes a
//  `updated_at > lastSyncedAt` filter so only changed records are fetched
//  after the initial full download. This keeps bandwidth proportional to
//  activity, not dataset size.
//
//  On the first sync (or after sign-in on a new device), `lastSyncedAt` is
//  nil and the full bounding-box dataset is fetched.
//
//  Antimeridian safety: the bounding box longitude filter is split into two
//  queries when it crosses ±180°, preventing invalid range comparisons for
//  users near the International Date Line (eastern Russia, Fiji, Alaska, etc.)
//
//  Conflict resolution: last-write-wins on `updated_at`.
//
//  ── Auth State ────────────────────────────────────────────────────────────
//
//  Three possible states, exposed as separate observable properties:
//    1. currentUser != nil         → fully authenticated
//    2. pendingConfirmationEmail  → signed up but email not yet confirmed
//    3. both nil                  → unauthenticated (show login)
//
//  GeoPoopApp switches on these to display the correct root view.
//
//  ── Profile Creation ──────────────────────────────────────────────────────
//
//  After sign-up, if the DB trigger that auto-creates a `profiles` row hasn't
//  fired yet, createProfile() inserts one directly. This eliminates the
//  fragile 600ms sleep that previously guarded against trigger lag.
//

import AuthenticationServices
import CoreLocation
import Foundation
import Observation
import SwiftData
import UIKit
import Supabase

// MARK: - UserProfile

struct UserProfile: Codable {
    var id:          UUID
    var displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

// MARK: - BathroomReport

struct BathroomReport: Codable {
    let bathroomID: UUID
    let reporterID: UUID
    let reason:     String   // ReportReason rawValue
    let notes:      String

    enum CodingKeys: String, CodingKey {
        case bathroomID = "bathroom_id"
        case reporterID = "reporter_id"
        case reason
        case notes
    }
}

// MARK: - SupabaseService

@Observable
final class SupabaseService {

    // MARK: - Auth State

    /// Non-nil when the user is fully authenticated.
    var currentUser: User?

    /// Non-nil when the user has signed up but not yet confirmed their email.
    /// GeoPoopApp uses this to show the EmailConfirmationView.
    var pendingConfirmationEmail: String?

    var userProfile: UserProfile?

    /// Current user's email. Callers use this instead of importing Auth directly.
    var currentUserEmail: String? { currentUser?.email }

    /// Current user's UUID as a String. Callers use this instead of importing Auth directly.
    var currentUserIDString: String? { currentUser?.id.uuidString }

    // MARK: - Operation State

    var isSyncing     = false
    var authError:    String?
    var lastSyncError: String?

    // MARK: - Private

    private let client = SupabaseConfig.client
    private let bucket = "bathroom-photos"

    // UserDefaults key for the stable Apple user ID (used for credential-state checks).
    // Not sensitive — just an opaque string issued by Apple.
    private let appleUserIDKey = "geo.poop.appleUserID"

    // MARK: - Init

    init() {
        // Restore any existing session from the Supabase SDK's keychain storage.
        // If a session exists, set currentUser immediately so GeoPoopApp renders
        // ContentView without flashing LoginView first.
        currentUser = client.auth.currentSession?.user
        if let user = currentUser {
            Task { await fetchProfile(for: user.id) }
        }
    }

    // MARK: - Auth: Sign In

    func signIn(email: String, password: String) async throws {
        authError = nil
        let session = try await client.auth.signIn(email: email, password: password)
        currentUser              = session.user
        pendingConfirmationEmail = nil
        await fetchProfile(for: session.user.id)
    }

    // MARK: - Auth: Sign Up

    func signUp(email: String, password: String) async throws {
        authError = nil
        let response = try await client.auth.signUp(email: email, password: password)

        // Supabase returns session == nil when email confirmation is required.
        // Don't set currentUser — show EmailConfirmationView instead.
        guard let session = response.session else {
            pendingConfirmationEmail = email
            return
        }

        currentUser              = session.user
        pendingConfirmationEmail = nil

        // Fetch the auto-created profile. If the DB trigger hasn't fired yet,
        // create the profile row directly — no sleep hacks needed.
        await fetchProfile(for: session.user.id)
        if userProfile == nil {
            try? await createProfile(for: session.user.id, email: email)
            await fetchProfile(for: session.user.id)
        }
    }

    // MARK: - Auth: Forgot Password

    /// Sends a password-reset email to the given address.
    /// Supabase delivers a magic link; tapping it opens the app (or a browser)
    /// where the user sets a new password.
    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
    }

    // MARK: - Auth: Apple Sign-In

    /// Exchanges an Apple identity token for a Supabase session.
    ///
    /// Apple only returns `fullName` on the FIRST authorization. The caller
    /// must pass it immediately — it is nil on subsequent sign-ins.
    ///
    /// Account linking: if a user with the same email already exists (e.g.
    /// via email/password), Supabase merges the Apple identity into that
    /// account automatically when "Allow manual linking" is enabled in the
    /// Supabase dashboard. No extra code required here.
    func signInWithApple(
        idToken: String,
        rawNonce: String,
        appleUserID: String,
        fullName: PersonNameComponents?
    ) async throws {
        authError = nil

        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: idToken,
                nonce: rawNonce
            )
        )

        currentUser              = session.user
        pendingConfirmationEmail = nil

        // Persist the stable Apple user ID so we can check credential state
        // on future launches without needing to go through a full sign-in.
        UserDefaults.standard.set(appleUserID, forKey: appleUserIDKey)

        // Determine if this is a brand-new user before we create a profile row.
        await fetchProfile(for: session.user.id)
        let isNewUser = userProfile == nil

        if isNewUser {
            try? await createProfile(for: session.user.id, email: session.user.email ?? "")
            await fetchProfile(for: session.user.id)
        }

        // Apply Apple-provided name only for new users — never overwrite a name
        // the user may have customised. Apple only sends fullName on first auth,
        // so we must handle it here rather than deferring to a profile-edit step.
        if isNewUser, let name = fullName {
            let displayName = [name.givenName, name.familyName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !displayName.isEmpty {
                try? await updateDisplayName(displayName)
            }
        }
    }

    /// Checks whether the saved Apple credential is still valid on launch.
    ///
    /// Call this once when the app becomes active. If Apple revokes the
    /// credential (user disables the app in Settings → Apple ID →
    /// Sign in with Apple), this will sign the user out locally so they
    /// are prompted to re-authenticate rather than reaching a broken state.
    func checkAppleCredentialState() async {
        guard currentUser != nil,
              let appleUserID = UserDefaults.standard.string(forKey: appleUserIDKey)
        else { return }

        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: appleUserID)
            switch state {
            case .authorized:
                break   // All good — nothing to do
            case .revoked, .notFound:
                // Credential revoked or not found — force sign-out
                try? await signOut()
            case .transferred:
                break   // App-transfer scenario — no action needed
            @unknown default:
                break
            }
        } catch {
            // Cannot determine state (e.g. no network) — leave user signed in
        }
    }

    // MARK: - Auth: Sign Out

    /// Signs out the current user and clears all locally cached data.
    ///
    /// Pass `clearingContext` to wipe the local SwiftData store so a subsequent
    /// user on the same device doesn't see the previous user's bathrooms until
    /// their sync overwrites them. Pass `syncQueue` to discard pending offline
    /// operations that belong to the outgoing user.
    func signOut(
        clearingContext context: ModelContext? = nil,
        syncQueue: SyncQueue? = nil
    ) async throws {
        try await client.auth.signOut()
        currentUser              = nil
        userProfile              = nil
        pendingConfirmationEmail = nil
        lastSyncError            = nil
        clearLastSyncedAt()
        UserDefaults.standard.removeObject(forKey: appleUserIDKey)

        syncQueue?.clear()

        if let context {
            try? context.delete(model: Bathroom.self)
            let imagesFolder = ImageStorage.documentsURL.appendingPathComponent("BathroomImages")
            try? FileManager.default.removeItem(at: imagesFolder)
        }
    }

    // MARK: - Profile

    func fetchProfile(for userID: UUID) async {
        do {
            let profile: UserProfile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userID.uuidString)
                .single()
                .execute()
                .value
            userProfile = profile
        } catch {
            // Profile may not exist yet immediately after sign-up — handled by caller.
        }
    }

    private func createProfile(for userID: UUID, email: String) async throws {
        let defaultName = email.components(separatedBy: "@").first ?? "Explorer"
        struct NewProfile: Encodable {
            let id: String
            let display_name: String
        }
        try await client
            .from("profiles")
            .insert(NewProfile(id: userID.uuidString, display_name: defaultName))
            .execute()
    }

    func updateDisplayName(_ name: String) async throws {
        guard let userID = currentUser?.id else { return }
        try await client
            .from("profiles")
            .update(["display_name": name])
            .eq("id", value: userID.uuidString)
            .execute()
        userProfile?.displayName = name
    }

    // MARK: - Sync (cloud → local)

    /// Downloads bathrooms visible to the current user and upserts them into SwiftData.
    ///
    /// Delta behaviour:
    ///   On first sync (or after forced reset), downloads the full bounding-box
    ///   dataset. On subsequent syncs, only records modified after the last sync
    ///   timestamp are fetched, keeping bandwidth proportional to activity.
    ///
    /// Antimeridian safety:
    ///   When the bounding box crosses ±180° longitude, two queries are run and
    ///   merged, preventing invalid range comparisons near the date line.
    ///
    /// Concurrency: overlapping calls are silently dropped (isSyncing guard).
    func syncAll(
        context: ModelContext,
        userLocation: CLLocationCoordinate2D? = nil,
        force: Bool = false
    ) async {
        guard currentUser != nil else { return }
        guard !isSyncing else { return }

        isSyncing = true
        defer { isSyncing = false }

        let syncStart = Date()

        do {
            let remote: [RemoteBathroom]

            if let loc = userLocation {
                remote = try await fetchBoundingBox(near: loc, force: force)
            } else if let uid = currentUser?.id.uuidString {
                // No location — fetch only this user's own bathrooms
                remote = try await client
                    .from("bathrooms")
                    .select()
                    .eq("owner_id", value: uid)
                    .execute()
                    .value
            } else {
                remote = []
            }

            for r in remote { upsertLocal(r, in: context) }
            lastSyncError = nil
            setLastSyncedAt(syncStart)

        } catch {
            lastSyncError = error.localizedDescription
            print("[Supabase] sync error: \(error)")
        }
    }

    // MARK: - Bounding Box Fetch (with antimeridian support)

    private func fetchBoundingBox(
        near loc: CLLocationCoordinate2D,
        force: Bool
    ) async throws -> [RemoteBathroom] {
        let delta  = 2.0   // ≈ ±220 km latitude; longitude varies by latitude
        let minLat = loc.latitude  - delta
        let maxLat = loc.latitude  + delta
        let minLon = loc.longitude - delta
        let maxLon = loc.longitude + delta

        let updatedAfter = force ? nil : lastSyncedAt()

        if minLon < -180 || maxLon > 180 {
            // Bounding box crosses the antimeridian — split into two queries
            // and merge the results to avoid invalid longitude range comparisons.
            let (wrapMinLon, wrapMaxLon) = antimeridianWrapped(min: minLon, max: maxLon)

            async let part1: [RemoteBathroom] = try fetchLatLonBox(
                minLat: minLat, maxLat: maxLat,
                minLon: wrapMinLon, maxLon: 180,
                updatedAfter: updatedAfter
            )
            async let part2: [RemoteBathroom] = try fetchLatLonBox(
                minLat: minLat, maxLat: maxLat,
                minLon: -180, maxLon: wrapMaxLon,
                updatedAfter: updatedAfter
            )
            return try await part1 + part2
        } else {
            return try await fetchLatLonBox(
                minLat: minLat, maxLat: maxLat,
                minLon: minLon, maxLon: maxLon,
                updatedAfter: updatedAfter
            )
        }
    }

    private func fetchLatLonBox(
        minLat: Double, maxLat: Double,
        minLon: Double, maxLon: Double,
        updatedAfter: Date?
    ) async throws -> [RemoteBathroom] {
        var query = client
            .from("bathrooms")
            .select()
            .gte("latitude",  value: minLat)
            .lte("latitude",  value: maxLat)
            .gte("longitude", value: minLon)
            .lte("longitude", value: maxLon)

        // Delta sync: only fetch records modified after the last successful sync
        if let after = updatedAfter {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            query = query.gt("updated_at", value: iso.string(from: after))
        }

        return try await query.execute().value
    }

    /// Computes the two longitude extremes for an antimeridian-crossing box.
    private func antimeridianWrapped(min: Double, max: Double) -> (Double, Double) {
        let wrapMin = min < -180 ? min + 360 : min   // e.g. -181 → 179
        let wrapMax = max >  180 ? max - 360 : max   // e.g.  181 → -179
        return (wrapMin, wrapMax)
    }

    // MARK: - Local Upsert

    private func upsertLocal(_ r: RemoteBathroom, in context: ModelContext) {
        let rid = r.id
        let descriptor = FetchDescriptor<Bathroom>(
            predicate: #Predicate { $0.id == rid }
        )

        if let existing = (try? context.fetch(descriptor))?.first {
            guard r.updatedAt > existing.dateModified else { return }
            applyRemote(r, to: existing)
        } else {
            let b = Bathroom(
                id:                     r.id,
                name:                   r.name,
                latitude:               r.latitude,
                longitude:              r.longitude,
                address:                r.address,
                rating:                 r.rating,
                accessType:             BathroomAccess(rawValue: r.accessType)       ?? .free,
                requiresReceiptCode:    r.requiresReceiptCode,
                isOpen24Hours:          r.isOpen24Hours,
                stallType:              StallType(rawValue: r.stallType)             ?? .single,
                genderType:             GenderType(rawValue: r.genderType)           ?? .allGender,
                isIndoor:               r.isIndoor,
                isWheelchairAccessible: r.isWheelchairAccessible,
                hasToiletPaper:         r.hasToiletPaper,
                hasExtraToiletPaper:    r.hasExtraToiletPaper,
                dispenserRating:        r.dispenserRating,
                hasHeatedSeat:          r.hasHeatedSeat,
                bidetType:              BidetType(rawValue: r.bidetType)             ?? .none,
                hasChangingTable:       r.hasChangingTable,
                hasSoap:                r.hasSoap,
                hasDryingOption:        r.hasDryingOption,
                waitTime:               WaitTime(rawValue: r.waitTime)               ?? .unknown,
                notes:                  r.notes,
                dateVisited:            r.dateVisited,
                dateCreated:            r.createdAt,
                imageFileNames:         r.photoPaths,
                isPrivate:              r.isPrivate,
                ownerID:                r.ownerID.uuidString,
                verificationCount:      r.verificationCount ?? 0,
                lastVerifiedAt:         r.lastVerifiedAt
            )
            context.insert(b)
        }
    }

    private func applyRemote(_ r: RemoteBathroom, to b: Bathroom) {
        b.name                   = r.name
        b.latitude               = r.latitude
        b.longitude              = r.longitude
        b.address                = r.address
        b.rating                 = r.rating
        b.accessType             = BathroomAccess(rawValue: r.accessType)       ?? .free
        b.requiresReceiptCode    = r.requiresReceiptCode
        b.isOpen24Hours          = r.isOpen24Hours
        b.stallType              = StallType(rawValue: r.stallType)             ?? .single
        b.genderType             = GenderType(rawValue: r.genderType)           ?? .allGender
        b.isIndoor               = r.isIndoor
        b.isWheelchairAccessible = r.isWheelchairAccessible
        b.hasToiletPaper         = r.hasToiletPaper
        b.hasExtraToiletPaper    = r.hasExtraToiletPaper
        b.dispenserRating        = r.dispenserRating
        b.hasHeatedSeat          = r.hasHeatedSeat
        b.bidetType              = BidetType(rawValue: r.bidetType)             ?? .none
        b.hasChangingTable       = r.hasChangingTable
        b.hasSoap                = r.hasSoap
        b.hasDryingOption        = r.hasDryingOption
        b.waitTime               = WaitTime(rawValue: r.waitTime)               ?? .unknown
        b.notes                  = r.notes
        b.dateVisited            = r.dateVisited
        b.dateModified           = r.updatedAt
        b.imageFileNames         = r.photoPaths
        b.isPrivate              = r.isPrivate
        b.verificationCount      = r.verificationCount ?? b.verificationCount
        b.lastVerifiedAt         = r.lastVerifiedAt    ?? b.lastVerifiedAt
        // dateCreated intentionally not updated — it should never change.
    }

    // MARK: - Push (local → cloud)

    func upsertRemote(_ bathroom: Bathroom) async throws {
        guard let user = currentUser else { return }
        if bathroom.ownerID.isEmpty { bathroom.ownerID = user.id.uuidString }
        let remote = RemoteBathroom(bathroom: bathroom, ownerID: user.id)
        try await client
            .from("bathrooms")
            .upsert(remote)
            .execute()
    }

    func deleteRemote(bathroomID: UUID) async throws {
        try await client
            .from("bathrooms")
            .delete()
            .eq("id", value: bathroomID.uuidString)
            .execute()
    }

    func deleteWithPhotos(bathroomID: UUID, fileNames: [String]) async {
        try? await deletePhotos(bathroomID: bathroomID, fileNames: fileNames)
        try? await deleteRemote(bathroomID: bathroomID)
    }

    // MARK: - Photo Storage

    func uploadPhoto(_ image: UIImage, bathroomID: UUID, fileName: String) async throws {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        let path = "\(bathroomID)/\(fileName)"
        try await client.storage
            .from(bucket)
            .upload(path, data: data,
                    options: FileOptions(contentType: "image/jpeg", upsert: true))
    }

    func downloadPhoto(bathroomID: UUID, fileName: String) async throws -> UIImage? {
        let path = "\(bathroomID)/\(fileName)"
        let data = try await client.storage.from(bucket).download(path: path)
        return UIImage(data: data)
    }

    func deletePhotos(bathroomID: UUID, fileNames: [String]) async throws {
        guard !fileNames.isEmpty else { return }
        let paths = fileNames.map { "\(bathroomID)/\($0)" }
        try await client.storage.from(bucket).remove(paths: paths)
    }

    // MARK: - Community Verification

    /// Increments the verification count and sets `last_verified_at` to now
    /// for the given bathroom, on both the server and the local model.
    func verifyBathroom(_ bathroom: Bathroom) async throws {
        let newCount = bathroom.verificationCount + 1
        let now      = Date()
        let iso      = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        try await client
            .from("bathrooms")
            .update([
                "verification_count": "\(newCount)",
                "last_verified_at":   iso.string(from: now)
            ])
            .eq("id", value: bathroom.id.uuidString)
            .execute()

        // Update the local model immediately (optimistic update)
        bathroom.verificationCount = newCount
        bathroom.lastVerifiedAt    = now
        bathroom.dateModified      = now
    }

    // MARK: - Report

    /// Submits a moderation report for a bathroom entry.
    func submitReport(bathroomID: UUID, reason: ReportReason, notes: String) async throws {
        guard let userID = currentUser?.id else { return }
        let report = BathroomReport(
            bathroomID: bathroomID,
            reporterID: userID,
            reason:     reason.rawValue,
            notes:      notes
        )
        try await client
            .from("reports")
            .insert(report)
            .execute()
    }

    // MARK: - Emergency Cloud Query

    /// Finds the nearest bathroom to `location` by querying Supabase directly.
    ///
    /// Used by the emergency handler when the local SwiftData store is empty
    /// (new device, first launch). Tries a small box first (≈ 55 km), then
    /// expands to the full ≈ 220 km box if nothing is found nearby.
    func findNearestBathroom(near location: CLLocationCoordinate2D) async throws -> RemoteBathroom? {
        let origin = CLLocation(latitude: location.latitude, longitude: location.longitude)

        // Try a smaller initial box (faster, more relevant results)
        for delta in [0.5, 2.0] {
            let results: [RemoteBathroom] = try await fetchLatLonBox(
                minLat:       location.latitude  - delta,
                maxLat:       location.latitude  + delta,
                minLon:       location.longitude - delta,
                maxLon:       location.longitude + delta,
                updatedAfter: nil
            )
            if let nearest = results.min(by: {
                CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: origin) <
                CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: origin)
            }) {
                return nearest
            }
        }
        return nil
    }

    // MARK: - Ownership

    func isOwner(of bathroom: Bathroom) -> Bool {
        guard let userID = currentUser?.id.uuidString else { return false }
        return bathroom.ownerID.lowercased() == userID.lowercased()
    }

    // MARK: - Delta Sync Timestamp (per user, stored in UserDefaults)

    private func lastSyncedAtKey() -> String? {
        guard let uid = currentUser?.id else { return nil }
        return "lastSyncedAt_\(uid.uuidString)"
    }

    private func lastSyncedAt() -> Date? {
        guard let key = lastSyncedAtKey() else { return nil }
        return UserDefaults.standard.object(forKey: key) as? Date
    }

    private func setLastSyncedAt(_ date: Date) {
        guard let key = lastSyncedAtKey() else { return }
        UserDefaults.standard.set(date, forKey: key)
    }

    private func clearLastSyncedAt() {
        guard let key = lastSyncedAtKey() else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }
}
