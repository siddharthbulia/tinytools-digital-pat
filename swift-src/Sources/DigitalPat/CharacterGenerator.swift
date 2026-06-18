import AppKit

/// Generates a full character (base + mood sprites) from a user photo via the OpenAI image API,
/// pixelates each in-app (Pixelate), and saves them to the user Characters folder so the new
/// character shows up in the switcher. Uses the user's own API key.
@MainActor
final class CharacterGenerator: ObservableObject {
    @Published var busy = false
    @Published var progress = ""
    @Published var error: String?

    // mood id -> "change only:" detail (base/neutral comes straight from the photo)
    private let moods: [(String, String)] = [
        ("coding",        "add small round eyeglasses, a cozy focused look"),
        ("thinking",      "add small round glasses and a little glowing yellow lightbulb floating above the head"),
        ("meeting",       "wearing a smart dark blazer, sitting up attentively"),
        ("communicating", "wearing small headphones with a tiny speech bubble floating beside the head"),
        ("browsing",      "holding a tiny smartphone in both hands, looking at it"),
        ("creating",      "holding a tiny paintbrush and a small artist palette"),
        ("vibing",        "wearing big headphones, eyes happily closed, a small music note floating"),
        ("idle",          "eyes closed and head gently drooping, sleepy resting pose, small Zzz floating"),
        ("pat",           "eyes happily closed in upward curved arcs, big rosy blush on the cheeks, a content smile"),
        ("blink",         "both eyes gently closed in a soft blink, content"),
    ]

    private let basePrompt = """
    Turn this person into an ADORABLE chibi pixel-art mascot in a cute retro Tamagotchi style. \
    The mascot MUST FACE THE VIEWER HEAD-ON — a front-facing, forward-looking, upright, centered \
    pose looking straight at the camera — NO MATTER how the source photo is angled, turned, or \
    cropped. Huge round head about 60% of the body, big sparkly low-set eyes with white catchlights, \
    tiny rounded body, sitting, thick clean outline, soft warm palette, transparent background, \
    single centered character. Keep their most recognizable features (hairstyle, facial hair, \
    glasses, skin tone, signature clothing/headwear).
    """

    /// Returns the new character id on success, or nil.
    func generate(name: String, photo: NSImage) async -> String? {
        busy = true; error = nil; defer { busy = false }
        let id = Self.slug(name)
        guard let photoPNG = png(photo) else { error = "Couldn't read that image."; return nil }

        progress = "drawing \(name)…"
        guard let baseRaw = await callBackend(prompt: basePrompt, image: photoPNG) else {
            error = error ?? "Generation failed. Check your connection and try again."
            return nil
        }
        guard let dir = try? makeDir(id),
              let baseImg = NSImage(data: baseRaw),
              let neutral = Pixelate.process(baseImg) else { error = "Couldn't process the image."; return nil }
        // neutral.png is load-bearing (it's the palette + the existence check for the character). Do NOT
        // swallow a failed write — otherwise we'd return a non-nil id, persist it as the active character,
        // and the pet would silently render the cat fallback (wedged across relaunches).
        do { try neutral.write(to: dir.appendingPathComponent("neutral.png")) }
        catch { self.error = "Couldn't save the new character — check disk space and try again."; return nil }

        let pre = "Keep this EXACT chibi pixel character identical — same face, same hair/headwear, " +
                  "same FRONT-FACING forward pose, same proportions and pixel-art style, transparent background. Change ONLY: "
        // moods whose eyes are open get a matching eyes-closed blink frame (same outfit)
        let blinkEligible: Set<String> = ["coding", "thinking", "meeting", "communicating", "browsing", "creating"]
        let blinkPre = "Keep this EXACT chibi pixel character identical — same outfit, same hair/headwear, " +
                       "same front-facing pose, same everything. Change ONLY: both eyes gently closed in a soft blink."
        var done = 1
        for (mood, detail) in moods {
            progress = "\(mood)… (\(done)/\(moods.count + 1))"
            if let raw = await callBackend(prompt: pre + detail, image: baseRaw),
               let img = NSImage(data: raw), let px = Pixelate.process(img) {
                try? px.write(to: dir.appendingPathComponent("\(mood).png"))
                if blinkEligible.contains(mood) {
                    progress = "\(mood) blink…"
                    if let braw = await callBackend(prompt: blinkPre, image: raw),
                       let bimg = NSImage(data: braw), let bpx = Pixelate.process(bimg) {
                        try? bpx.write(to: dir.appendingPathComponent("\(mood)-blink.png"))
                    }
                }
            }
            done += 1
        }
        progress = "done!"
        Sprites.clear(characterId: id)   // drop any cached frames so the freshly-written PNGs are used
        guard Characters.shared.dir(for: id) != nil else {   // belt-and-suspenders: never return a wedged id
            error = "Couldn't save the new character."; return nil
        }
        return id
    }

    // MARK: - Image generation (via the Supabase Edge Function)

    private func callBackend(prompt: String, image: Data) async -> Data? {
        // The function is deployed with --verify-jwt, so we must send the user's auth token.
        guard let token = await SupabaseService.shared.accessToken() else {
            error = "Couldn't sign in. Check your connection and try again."
            return nil
        }
        var req = URLRequest(url: URL(string: Backend.url)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(Backend.anonKey, forHTTPHeaderField: "apikey")
        req.setValue(Backend.sharedSecret, forHTTPHeaderField: "x-pat-secret")
        req.timeoutInterval = 300

        let payload: [String: Any] = [
            "image": image.base64EncodedString(),
            "prompt": prompt,
            "size": "1024x1024",
            "quality": "medium",
            "background": "transparent",
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                let msg = String(data: data, encoding: .utf8) ?? ""
                error = "Server error: \(msg.prefix(160))"
                return nil
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let b64 = obj["b64_json"] as? String,
                  let img = Data(base64Encoded: b64) else { error = "Unexpected response."; return nil }
            return img
        } catch {
            self.error = "Network error: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - helpers

    private func png(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    private func makeDir(_ id: String) throws -> URL {
        let dir = Characters.userRoot().appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func slug(_ name: String) -> String {
        let base = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        var s = String(base).replacingOccurrences(of: "--", with: "-").trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if s.isEmpty { s = "character" }
        if s == "cat" || s == "gd" { s += "-1" }
        return s
    }
}
