import AppKit

/// Loads character sprites. A character is a folder of mood PNGs (named by Mood.rawValue) plus
/// "pat"/"blink"/per-mood blinks. Everything is character-scoped so the same renderer (PetState +
/// CatView) can draw my pet AND my friends' pets. Cache is keyed by "characterId/name".
enum Sprites {
    private static var cache: [String: NSImage] = [:]

    /// Raw load of `<characterId>/<name>.png`, nil if missing. Cached.
    static func raw(_ characterId: String, _ name: String) -> NSImage? {
        let key = "\(characterId)/\(name)"
        if let cached = cache[key] { return cached }
        guard let dir = Characters.shared.dir(for: characterId),
              let img = NSImage(contentsOf: dir.appendingPathComponent("\(name).png")) else { return nil }
        cache[key] = img
        return img
    }

    static func clearCache() { cache.removeAll() }

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
