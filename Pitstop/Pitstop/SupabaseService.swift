import AuthenticationServices
import CoreLocation
import Foundation
import Observation
import os
import SwiftData
import UIKit
import Supabase

private let logger = Logger(subsystem: "Pitstop", category: "SupabaseService")

// MARK: - UserProfile

nonisolated struct UserProfile: Codable {
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

/// Owns auth, profile, sync, photo storage, verification and reporting against the backend.
@Observable
final class SupabaseService {

    // MARK: - Auth State

    var currentUser: User?

    /// Set after sign-up when email confirmation is still pending.
    var pendingConfirmationEmail: String?

    var userProfile: UserProfile?

    // Exposed so callers don't need to import the SDK's Auth types.
    var currentUserEmail: String? { currentUser?.email }

    var currentUserIDString: String? { currentUser?.id.uuidString }

    // MARK: - Operation State

    var isSyncing     = false
    var authError:    String?
    var lastSyncError: String?

    // MARK: - Private

    private let client = BackendConfig.client
    private let bucket = "bathroom-photos"

    // Apple's stable user ID, kept for credential-state checks on launch.
    private let appleUserIDKey = "geo.poop.appleUserID"

    // MARK: - Init

    init() {
        // Restore the keychain session synchronously so the first frame isn't the login screen.
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

        // No session means email confirmation is required.
        guard let session = response.session else {
            pendingConfirmationEmail = email
            return
        }

        currentUser              = session.user
        pendingConfirmationEmail = nil

        // A DB trigger normally creates the profile row; create it here if the trigger hasn't run yet.
        await fetchProfile(for: session.user.id)
        if userProfile == nil {
            try? await createProfile(for: session.user.id, email: email)
            await fetchProfile(for: session.user.id)
        }
    }

    // MARK: - Auth: Forgot Password

    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
    }

    // MARK: - Auth: Apple Sign-In

    /// Exchanges an Apple identity token for a backend session.
    /// `fullName` is only provided by Apple on the first authorization.
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

        UserDefaults.standard.set(appleUserID, forKey: appleUserIDKey)

        await fetchProfile(for: session.user.id)
        let isNewUser = userProfile == nil

        if isNewUser {
            try? await createProfile(for: session.user.id, email: session.user.email ?? "")
            await fetchProfile(for: session.user.id)
        }

        // Only seed the name for new users so a customized name is never overwritten.
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

    /// Signs out if the user revoked Sign in with Apple for this app since the last launch.
    func checkAppleCredentialState() async {
        guard currentUser != nil,
              let appleUserID = UserDefaults.standard.string(forKey: appleUserIDKey)
        else { return }

        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: appleUserID)
            switch state {
            case .authorized:
                break
            case .revoked, .notFound:
                try? await signOut()
            case .transferred:
                break
            @unknown default:
                break
            }
        } catch {
            // State unknown (e.g. offline): leave the user signed in.
        }
    }

    // MARK: - Auth: Sign Out

    /// Pass `clearingContext` and `syncQueue` to wipe local bathrooms, images and
    /// queued operations so the next user on the device starts clean.
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
            // The row may not exist yet right after sign-up; callers handle a nil profile.
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

    /// Pulls bathrooms visible to the user into SwiftData, last write wins on `updated_at`.
    /// After the first sync only rows changed since the last one are fetched (`force` refetches all).
    /// Overlapping calls are dropped.
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
                // Without a location, fall back to the user's own bathrooms.
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
            logger.error("Sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Bounding Box Fetch

    private func fetchBoundingBox(
        near loc: CLLocationCoordinate2D,
        force: Bool
    ) async throws -> [RemoteBathroom] {
        let delta  = 2.0   // degrees; about 220 km of latitude each way
        let minLat = loc.latitude  - delta
        let maxLat = loc.latitude  + delta
        let minLon = loc.longitude - delta
        let maxLon = loc.longitude + delta

        let updatedAfter = force ? nil : lastSyncedAt()

        if minLon < -180 || maxLon > 180 {
            // A box crossing ±180° has minLon > maxLon once wrapped, which no single
            // range filter can express, so query each side of the antimeridian and merge.
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

        if let after = updatedAfter {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            query = query.gt("updated_at", value: iso.string(from: after))
        }

        return try await query.execute().value
    }

    private func antimeridianWrapped(min: Double, max: Double) -> (Double, Double) {
        let wrapMin = min < -180 ? min + 360 : min
        let wrapMax = max >  180 ? max - 360 : max
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

    /// Bumps the verification count and `last_verified_at` on the server, then locally.
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

        bathroom.verificationCount = newCount
        bathroom.lastVerifiedAt    = now
        bathroom.dateModified      = now
    }

    // MARK: - Report

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

    /// Server-side nearest-bathroom lookup for when the local store is empty.
    /// Tries a 0.5° box (about 55 km) before widening to 2°.
    func findNearestBathroom(near location: CLLocationCoordinate2D) async throws -> RemoteBathroom? {
        let origin = CLLocation(latitude: location.latitude, longitude: location.longitude)

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

    // MARK: - Delta Sync Timestamp (per user)

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
