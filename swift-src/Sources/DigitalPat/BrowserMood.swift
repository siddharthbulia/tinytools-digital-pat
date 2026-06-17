import AppKit
import Foundation

/// Refines Pat's mood from the active BROWSER TAB's domain (e.g. youtube.com → vibing).
/// Reads only the domain via AppleScript — never the path, query, page content, or keystrokes.
/// Sending Apple Events to another app triggers the macOS Automation permission prompt
/// (and needs NSAppleEventsUsageDescription + the apple-events entitlement). If the user
/// denies it, every call simply returns nil and Pat falls back to the app-level "browsing".
enum BrowserMood {
    /// bundle id → AppleScript that returns the active tab's URL.
    private static let scripts: [String: String] = [
        "com.google.Chrome":          "tell application id \"com.google.Chrome\" to get URL of active tab of front window",
        "com.google.Chrome.canary":   "tell application id \"com.google.Chrome.canary\" to get URL of active tab of front window",
        "com.brave.Browser":          "tell application id \"com.brave.Browser\" to get URL of active tab of front window",
        "com.microsoft.edgemac":      "tell application id \"com.microsoft.edgemac\" to get URL of active tab of front window",
        "company.thebrowser.Browser": "tell application id \"company.thebrowser.Browser\" to get URL of active tab of front window",
        "com.apple.Safari":           "tell application id \"com.apple.Safari\" to get URL of current tab of front window",
    ]

    static func isBrowser(_ bundleId: String?) -> Bool {
        guard let b = bundleId else { return false }
        return scripts[b] != nil
    }

    /// The active tab's domain (e.g. "github.com"), or nil. Domain only — never the path/title.
    static func activeHost(forBundleId bundleId: String?) -> String? {
        guard let b = bundleId, let src = scripts[b] else { return nil }
        guard let url = run(src) else { return nil }
        return host(from: url)
    }

    private static func run(_ src: String) -> String? {
        var err: NSDictionary?
        guard let s = NSAppleScript(source: src) else { return nil }
        let out = s.executeAndReturnError(&err)
        if err != nil { return nil }                 // not authorized / no window / etc.
        let v = out.stringValue
        return (v?.isEmpty == false) ? v : nil
    }

    private static func host(from urlString: String) -> String? {
        guard let u = URL(string: urlString), let h = u.host?.lowercased() else { return nil }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    static func mood(forHost host: String) -> Mood {
        func any(_ needles: [String]) -> Bool { needles.contains { host.contains($0) } }
        // order matters — specific google properties before the generic fallback
        if any(["meet.google", "zoom.us", "whereby.com", "around.co"]) { return .meeting }
        if any(["mail.google", "gmail", "outlook", "slack.com", "discord.com",
                "web.whatsapp", "messenger.com", "teams.microsoft", "web.telegram"]) { return .communicating }
        if any(["docs.google", "notion.so", "notion.site", "medium.com", "substack.com", "wikipedia.org"]) { return .thinking }
        if any(["chatgpt.com", "chat.openai", "claude.ai", "perplexity.ai", "gemini.google", "bard.google"]) { return .thinking }
        if any(["youtube.com", "netflix.com", "twitch.tv", "spotify.com", "music.apple",
                "soundcloud", "hulu.com", "disneyplus", "primevideo"]) { return .vibing }
        if any(["github", "gitlab", "bitbucket", "stackoverflow", "localhost", "127.0.0.1",
                "vercel.app", "vercel.com", "codepen", "codesandbox", "replit", "npmjs.com", "developer."]) { return .coding }
        if any(["figma.com", "canva.com", "photopea", "miro.com", "framer.com", "dribbble", "behance"]) { return .creating }
        return .browsing
    }
}
