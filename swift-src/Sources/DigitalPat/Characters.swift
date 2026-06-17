import AppKit

extension Notification.Name {
    /// Posted whenever the active character changes (onboarding pick, tray menu, friend sync).
    /// AppDelegate observes this so the live pet + friend-broadcast update from a single source.
    static let patCharacterChanged = Notification.Name("patCharacterChanged")
}

/// Manages which "character" (sprite set) is active. A character is a folder of mood PNGs
/// (neutral, coding, … , pat, blink). Bundled characters live in Resources/Characters/<id>/;
/// user-generated ones in ~/Library/Application Support/DigitalPat/Characters/<id>/.
final class Characters {
    static let shared = Characters()

    private let key = "digitalpat.character"
    private(set) var currentId: String

    private init() {
        currentId = UserDefaults.standard.string(forKey: key) ?? "cat"
    }

    // MARK: locations

    static func userRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DigitalPat/Characters", isDirectory: true)
    }

    private func bundleDir(_ id: String) -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Characters/\(id)", isDirectory: true)
    }
    private func userDir(_ id: String) -> URL {
        Self.userRoot().appendingPathComponent(id, isDirectory: true)
    }
    private func hasNeutral(_ dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("neutral.png").path)
    }

    /// Resolved sprite folder for an id (user copy wins over bundled).
    func dir(for id: String) -> URL? {
        let u = userDir(id)
        if hasNeutral(u) { return u }
        if let b = bundleDir(id), hasNeutral(b) { return b }
        return nil
    }

    // MARK: listing + selection

    func availableIds() -> [String] {
        var ids: [String] = []
        func scan(_ root: URL?) {
            guard let root, let items = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
            for it in items where (try? it.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                if hasNeutral(it), !ids.contains(it.lastPathComponent) { ids.append(it.lastPathComponent) }
            }
        }
        scan(Bundle.main.resourceURL?.appendingPathComponent("Characters", isDirectory: true))
        scan(Self.userRoot())
        if ids.isEmpty { ids = ["cat"] }
        // keep cat & gd first, then the rest alphabetically
        let priority = ["cat", "gd"]
        return ids.sorted { a, b in
            let ia = priority.firstIndex(of: a) ?? Int.max
            let ib = priority.firstIndex(of: b) ?? Int.max
            return ia != ib ? ia < ib : a < b
        }
    }

    func displayName(_ id: String) -> String {
        switch id {
        case "cat": return "Cat 🐱"
        case "gd":  return "GD 🧑"
        default:    return id.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    func setCurrent(_ id: String) {
        guard currentId != id else { return }
        currentId = id
        UserDefaults.standard.set(id, forKey: key)
        NotificationCenter.default.post(name: .patCharacterChanged, object: nil)
    }
}
