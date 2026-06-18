import AppKit

/// Loads character sprites. A character is a folder of mood PNGs (named by Mood.rawValue) plus
/// "pat"/"blink"/per-mood blinks. Everything is character-scoped so the same renderer (PetState +
/// CatView) can draw my pet AND my friends' pets. Cache is keyed by "characterId/name".
enum Sprites {
    // Value is NSImage? so MISSES are cached too (many per-mood frames legitimately don't exist for a
    // character — without negative caching every blink/perk tick re-runs FileManager + a failing
    // NSImage(contentsOf:) for the life of the always-running process).
    private static var cache: [String: NSImage?] = [:]

    /// Raw load of `<characterId>/<name>.png`, nil if missing. Cached (hits AND misses).
    static func raw(_ characterId: String, _ name: String) -> NSImage? {
        let key = "\(characterId)/\(name)"
        if let cached = cache[key] { return cached }   // outer optional present → we've probed before
        let img = Characters.shared.dir(for: characterId)
            .flatMap { NSImage(contentsOf: $0.appendingPathComponent("\(name).png")) }
        cache[key] = img
        return img
    }

    static func clearCache() { cache.removeAll() }

    /// Evict every cached frame for one character — call after (re)generating it so the new PNGs are
    /// picked up instead of the stale cached NSImage.
    static func clear(characterId id: String) {
        let prefix = "\(id)/"
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
    }

    // MARK: character-scoped

    /// Mood image for a character, falling back to that character's neutral, then the bundled cat.
    static func image(characterId: String, mood: String) -> NSImage? {
        if let img = raw(characterId, mood) { return img }
        if mood != "neutral", let n = raw(characterId, "neutral") { return n }
        if characterId != "cat" { return image(characterId: "cat", mood: mood) }
        return nil
    }

    /// A named sprite for a character (e.g. "pat", "blink", "coding-blink"); nil if missing.
    static func named(characterId: String, _ name: String) -> NSImage? { raw(characterId, name) }
}
