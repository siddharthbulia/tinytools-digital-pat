import Foundation
import Supabase

/// Central Supabase client for Digital Pat. Holds the authed client, signs the user in
/// anonymously on launch (persistent identity), and exposes the access token + uid that the
/// generation backend and friend-graph realtime layer need. supabase-swift persists the session
/// locally (Keychain on Apple platforms), so the same anonymous identity survives relaunches.
@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        // PAT_INSTANCE namespaces the stored session so multiple app copies on ONE device get
        // distinct anonymous identities (for testing). Unset in shipped builds → default behavior.
        let instance = ProcessInfo.processInfo.environment["PAT_INSTANCE"]
        let options = SupabaseClientOptions(
            auth: .init(storageKey: instance.map { "pat.auth.\($0)" })
        )
        client = SupabaseClient(
            supabaseURL: URL(string: "https://cpfbipbdsokoshzgqvsr.supabase.co")!,
            supabaseKey: Backend.anonKey,
            options: options
        )
    }

    /// Make sure we have a valid session (anonymous if first run). Returns the user id string,
    /// LOWERCASED — Foundation's `UUID.uuidString` is uppercase, but Postgres/PostgREST serialize
    /// uuids lowercase. Friend uids come back lowercase from `my_friends`, so we must lowercase
    /// ours too, or the per-friendship presence channel topic (min/max of the two uids) and the
    /// payload.uid comparisons would mismatch and presence would never connect.
    @discardableResult
    func ensureSession() async -> String? {
        if let s = try? await client.auth.session {
            return s.user.id.uuidString.lowercased()
        }
        do {
            let s = try await client.auth.signInAnonymously()
            return s.user.id.uuidString.lowercased()
        } catch {
            NSLog("Digital Pat: anonymous sign-in failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// A fresh access token (JWT) for authenticated calls; nil if not signed in.
    func accessToken() async -> String? {
        (try? await client.auth.session)?.accessToken
    }
}
