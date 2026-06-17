import SwiftUI

/// The kitten's mood, derived purely from which app is frontmost.
/// We never read window titles, URLs, or content — only the app identity.
enum Mood: String, CaseIterable, Identifiable {
    case coding
    case thinking
    case meeting
    case communicating
    case browsing
    case creating
    case vibing
    case idle
    case neutral

    var id: String { rawValue }

    var label: String {
        switch self {
        case .coding:        return "Coding"
        case .thinking:      return "Thinking"
        case .meeting:       return "In a meeting"
        case .communicating: return "Communicating"
        case .browsing:      return "Browsing"
        case .creating:      return "Creating"
        case .vibing:        return "Vibing"
        case .idle:          return "Napping"
        case .neutral:       return "Hanging out"
        }
    }

    var emoji: String {
        switch self {
        case .coding:        return "💻"
        case .thinking:      return "💡"
        case .meeting:       return "👔"
        case .communicating: return "💬"
        case .browsing:      return "🌐"
        case .creating:      return "🎨"
        case .vibing:        return "🎧"
        case .idle:          return "💤"
        case .neutral:       return "🐱"
        }
    }

    /// Rotating one-liners shown in the speech bubble.
    var captions: [String] {
        switch self {
        case .coding:        return ["locked in 💻", "shipping…", "tippy tappy ⌨️"]
        case .thinking:      return ["big brain time 💡", "hmm…", "cooking 🧠"]
        case .meeting:       return ["in a call 🎧", "looking pro 👔", "on mute fr"]
        case .communicating: return ["replying… 📨", "inbox grind", "brb texting"]
        case .browsing:      return ["just browsing 👀", "ooh 👀", "rabbit hole 🕳️"]
        case .creating:      return ["in the zone 🎨", "making things", "art mode"]
        case .vibing:        return ["vibing 🎶", "lo-fi hours", "🎵🎵🎵"]
        case .idle:          return ["napping 💤", "brb dreaming", "zzz"]
        case .neutral:       return ["hi! 👋", "i'm Pat 🐱", "pat me!"]
        }
    }

    var patCaptions: [String] { ["♡", "hehe", "hi!!", "prrr ♡", ":3"] }

    /// Accent used for the speech bubble + small mood touches.
    var accent: Color {
        switch self {
        case .coding:        return Color(red: 0.40, green: 0.55, blue: 1.00)
        case .thinking:      return Color(red: 1.00, green: 0.78, blue: 0.30)
        case .meeting:       return Color(red: 0.36, green: 0.42, blue: 0.55)
        case .communicating: return Color(red: 0.40, green: 0.80, blue: 0.70)
        case .browsing:      return Color(red: 0.55, green: 0.80, blue: 1.00)
        case .creating:      return Color(red: 0.95, green: 0.55, blue: 0.75)
        case .vibing:        return Color(red: 0.70, green: 0.55, blue: 1.00)
        case .idle:          return Color(red: 0.62, green: 0.62, blue: 0.74)
        case .neutral:       return Color(red: 1.00, green: 0.56, blue: 0.69)
        }
    }

    // MARK: drawing flags
    var glasses: Bool   { self == .coding || self == .thinking }
    var headphones: Bool { self == .meeting || self == .communicating || self == .vibing }
    var beret: Bool     { self == .creating }
    var nightcap: Bool  { self == .idle }
    var tie: Bool       { self == .meeting }
    var eyesClosed: Bool { self == .idle || self == .vibing }

    func randomCaption() -> String { captions.randomElement() ?? label }

    // MARK: app → mood mapping (static, shipped in the app)
    static func from(bundleId: String?, appName: String?) -> Mood {
        let bid = (bundleId ?? "").lowercased()
        let name = (appName ?? "").lowercased()

        func matchesAny(_ needles: [String]) -> Bool {
            for n in needles where !n.isEmpty {
                if bid.contains(n) || name.contains(n) { return true }
            }
            return false
        }

        if matchesAny(["vscode", "com.microsoft.vscode", "xcode", "iterm", "com.apple.terminal",
                       "warp", "cursor", "zed", "sublimetext", "jetbrains", "nova", "ghostty",
                       "alacritty", "kitty", "wezterm", "code"]) {
            return .coding
        }
        if matchesAny(["anthropic.claude", "openai.chat", "chatgpt", "perplexity", "com.apple.preview"]) {
            return .thinking
        }
        if matchesAny(["zoom", "us.zoom", "microsoft.teams", "facetime", "webex", "bluejeans",
                       "google.meet", "around"]) {
            return .meeting
        }
        if matchesAny(["slack", "com.apple.mail", "mobilesms", "messages", "discord", "telegram",
                       "whatsapp", "spark", "outlook", "front"]) {
            return .communicating
        }
        if matchesAny(["figma", "photoshop", "sketch", "canva", "finalcut", "illustrator",
                       "affinity", "blender", "procreate", "pixelmator"]) {
            return .creating
        }
        if matchesAny(["spotify", "com.apple.music", "com.apple.tv", "netflix", "vlc", "soundcloud"]) {
            return .vibing
        }
        if matchesAny(["chrome", "safari", "firefox", "thebrowser.browser", "arc", "brave",
                       "edge", "opera", "vivaldi", "orion"]) {
            return .browsing
        }
        return .neutral
    }
}
