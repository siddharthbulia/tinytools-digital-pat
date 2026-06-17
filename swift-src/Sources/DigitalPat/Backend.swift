import Foundation

/// Server-side image generation. The OpenAI key lives in a Supabase Edge Function
/// (project `digital-pat`), so users never enter a key. The app authenticates with the
/// project's anon key + a shared secret. (The shared secret only deters casual abuse —
/// it's extractable from the binary; real protection would be server-side rate limiting.)
enum Backend {
    static let url = "https://cpfbipbdsokoshzgqvsr.supabase.co/functions/v1/generate-image"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNwZmJpcGJkc29rb3NoemdxdnNyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE1MzM2NDIsImV4cCI6MjA5NzEwOTY0Mn0.uzWBpZi2YSCHnWwrqbmh7kYDCXKBW-zhw0k_pks6iIU"
    static let sharedSecret = "56aa1a7a1d399707c4e31c485d4da055c2848eb43cf33922"
}
