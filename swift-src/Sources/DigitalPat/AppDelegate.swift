import AppKit
import SwiftUI
import ServiceManagement
import Sparkle
import Combine

/// A borderless floating panel that never steals focus from the user's work.
final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Right-click on the pet → AppDelegate pops up the pet-control menu. SwiftUI doesn't handle
    /// right-click here (no .contextMenu on the own pet), so the event propagates up to the panel.
    var onRightClick: ((NSEvent) -> Void)?
    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let state = PetState()
    private var statusItem: NSStatusItem!
    private var petPanel: PetPanel!

    private var dragging = false
    private var grabOffset = CGSize.zero
    private let posKey = "digitalpat.petOrigin"
    private let roamKey = "pat.keepRoaming"

    private var roamer: Roamer?
    private var reactor: CursorReactor?
    private var modeObserver: AnyCancellable?   // mirrors cursorMode → roamer calm (Chipkoo suppresses roaming)

    private var addCharWindow: NSWindow?
    private var friendsWindow: NSWindow?

    /// Sparkle auto-updater: starts background checks (per Info.plist) and powers "Check for Updates…".
    private let updater = SPUStandardUpdaterController(startingUpdater: true,
                                                      updaterDelegate: nil,
                                                      userDriverDelegate: nil)

    /// When ON, Pat roams the screen on her own (corners, middle, edges). Default OFF — she stays
    /// where she is and only moves via your cursor (attract/push) or a drag.
    private var keepRoaming: Bool { UserDefaults.standard.bool(forKey: roamKey) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance (skipped for multi-identity testing via PAT_INSTANCE).
        if ProcessInfo.processInfo.environment["PAT_INSTANCE"] == nil {
            let running = NSWorkspace.shared.runningApplications.filter {
                $0.bundleIdentifier == Bundle.main.bundleIdentifier
            }
            if running.count > 1 { NSApp.terminate(nil); return }
        }

        installMainMenu()   // gives text fields the Edit menu → Cmd+C/V/X work (e.g. paste invite code)
        setupStatusItem()
        setupPetPanel()
        state.start()

        // Single source of truth for "the character changed" — onboarding, tray menu, and the
        // Add-Character flow all just call Characters.setCurrent(); this observer reflects it onto
        // the live pet AND broadcasts it to friends. No path can update one without the other.
        NotificationCenter.default.addObserver(
            self, selector: #selector(characterChanged), name: .patCharacterChanged, object: nil)
        // Friends always live on your desktop (Model A — mutual friend graph, no rooms).
        FriendStore.shared.onFriendsChanged = { friends in PresencePetsController.shared.sync(friends) }
        let env = ProcessInfo.processInfo.environment
        Task {
            await SupabaseService.shared.ensureSession()
            // Debug: PAT_NAME forces onboarding (multi-identity testing). Else auto-start if onboarded.
            if let dbgName = env["PAT_NAME"], !dbgName.isEmpty {
                let ch = env["PAT_CHAR"] ?? Characters.shared.currentId
                Characters.shared.setCurrent(ch); state.refreshCharacter()
                await FriendStore.shared.start(name: dbgName, character: ch)
            } else if FriendStore.shared.hasOnboarded {
                await FriendStore.shared.start(name: FriendStore.shared.myDisplayName,
                                               character: Characters.shared.currentId)
            }
        }
        if env["PAT_ADDCHAR"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showAddCharacter() }
        }
        if env["PAT_FRIENDS"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.showFriends() }
        }
    }

    // MARK: main menu

    /// LSUIElement apps get NO default menu, so standard editing commands (Cmd+C/V/X, Select All)
    /// never reach the responder chain — that's why the invite-code field wouldn't paste. Install a
    /// minimal App + Edit menu; the items use the standard first-responder selectors (paste(_:) etc.)
    /// so any focused NSTextField/NSTextView handles them.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Digital Pat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    // MARK: tray

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "🐱"
            button.toolTip = "Digital Pat — your desktop kitten"
            button.action = #selector(statusClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

    }

    @objc private func statusClicked(_ sender: AnyObject?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            showFriends()
        }
    }

    private func showContextMenu() {
        // App-level controls live in the tray. Per-pet controls (Hide / Roaming / Cursor / Character)
        // moved onto the pet itself (right-click your own pet). "Show Pat" stays here ONLY while hidden,
        // since you can't right-click a pet you can't see.
        let menu = NSMenu()
        menu.addItem(withTitle: "Friends 🐾", action: #selector(menuFriends), keyEquivalent: "")
        menu.addItem(.separator())
        if state.isHidden {
            menu.addItem(withTitle: "Show Pat", action: #selector(menuToggleHide), keyEquivalent: "")
        }
        let loginItem = NSMenuItem(title: "Launch at Login",
                                   action: #selector(menuToggleLogin), keyEquivalent: "")
        loginItem.state = launchesAtLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(menuCheckUpdates), keyEquivalent: "")
        menu.addItem(withTitle: "Reset Pat… (start over)", action: #selector(menuReset), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Digital Pat", action: #selector(menuQuit), keyEquivalent: "q")
        for item in menu.items { item.target = self }

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // restore click toggling afterwards
    }

    /// Per-pet controls, popped up when you right-click YOUR OWN pet (friend pets keep their own
    /// "Remove friend" menu). Reuses the exact handlers the tray used to host.
    private func petControlMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: state.isHidden ? "Show Pat" : "Hide Pat",
                     action: #selector(menuToggleHide), keyEquivalent: "")
        let roam = NSMenuItem(title: "Roaming freely", action: #selector(menuToggleRoaming), keyEquivalent: "")
        roam.state = keepRoaming ? .on : .off
        menu.addItem(roam)

        let cursorMenu = NSMenu()
        for m in CursorMode.allCases {
            let it = NSMenuItem(title: m.label, action: #selector(menuPickCursorMode(_:)), keyEquivalent: "")
            it.representedObject = m.rawValue
            it.state = (m == state.cursorMode) ? .on : .off
            it.target = self
            cursorMenu.addItem(it)
        }
        let cursorItem = NSMenuItem(title: "Cursor", action: nil, keyEquivalent: "")
        cursorItem.submenu = cursorMenu
        menu.addItem(cursorItem)

        let charMenu = NSMenu()
        for id in Characters.shared.availableIds() {
            let it = NSMenuItem(title: Characters.shared.displayName(id),
                                action: #selector(menuPickCharacter(_:)), keyEquivalent: "")
            it.representedObject = id
            it.state = (id == Characters.shared.currentId) ? .on : .off
            it.target = self
            charMenu.addItem(it)
        }
        charMenu.addItem(.separator())
        let addItem = NSMenuItem(title: "Add Character…", action: #selector(menuAddCharacter), keyEquivalent: "")
        addItem.target = self
        charMenu.addItem(addItem)
        let charItem = NSMenuItem(title: "Character", action: nil, keyEquivalent: "")
        charItem.submenu = charMenu
        menu.addItem(charItem)

        for item in menu.items { item.target = self }
        return menu
    }

    private func showPetMenu(_ ev: NSEvent) {
        guard let cv = petPanel.contentView else { return }
        petControlMenu().popUp(positioning: nil, at: cv.convert(ev.locationInWindow, from: nil), in: cv)
    }

    @objc private func menuToggleHide() { toggleHidden() }
    @objc private func menuToggleLogin() { toggleLaunchAtLogin() }
    @objc private func menuToggleRoaming() {
        let roam = !keepRoaming
        UserDefaults.standard.set(roam, forKey: roamKey)
        roamer?.setCalm(!roam)                // calm = NOT roaming
    }
    @objc private func screensChanged() {
        // Don't re-anchor; just rescue Pat if a display change left her off every screen.
        let size = petPanel.frame.size
        if !visibleSomewhere(origin: petPanel.frame.origin, size: size) { setTopRight(size: size) }
    }
    @objc private func menuPickCharacter(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Characters.shared.setCurrent(id)   // → posts .patCharacterChanged → characterChanged()
    }

    /// Fired by Characters.setCurrent(). Reflects the new character on the live pet and tells friends.
    @objc private func characterChanged() {
        state.refreshCharacter()
        FriendStore.shared.setCharacter(Characters.shared.currentId)
    }

    @objc private func menuPickCursorMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let mode = CursorMode.from(raw)
        // Just write state.cursorMode — the reactor OBSERVES it (Combine), so there's one wiring path
        // for own + friend pets. Chipkoo goes through enterChipkoo() so it mints a fresh cling epoch.
        if mode == .chipkoo { state.enterChipkoo() } else { state.cursorMode = mode }
    }

    @objc private func menuFriends() { showFriends() }

    private func showFriends() {
        if friendsWindow == nil {
            let host = NSHostingController(rootView: FriendsRootView())
            let win = NSWindow(contentViewController: host)
            win.title = "Digital Pat · Friends"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.delegate = self
            friendsWindow = win
        }
        NSApp.setActivationPolicy(.regular)
        friendsWindow?.center()
        friendsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func menuAddCharacter() { showAddCharacter() }

    private func showAddCharacter() {
        if addCharWindow == nil {
            let view = AddCharacterView(
                onDone: { [weak self] id in self?.finishAddCharacter(id) },
                onClose: { [weak self] in self?.closeAddCharacter() }
            )
            let host = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: host)
            win.title = "Add Character"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.delegate = self
            addCharWindow = win
        }
        NSApp.setActivationPolicy(.regular)   // let the accessory app show a real, focusable window
        addCharWindow?.center()
        addCharWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishAddCharacter(_ id: String) {
        Characters.shared.setCurrent(id)   // → posts .patCharacterChanged → characterChanged()
        closeAddCharacter()
    }

    private func closeAddCharacter() {
        addCharWindow?.orderOut(nil)
        restoreAccessoryIfNoWindows(except: addCharWindow)
    }

    /// Only return to menu-bar-only (.accessory) once the LAST managed window is gone — otherwise
    /// closing one window while the other is still open would demote the surviving window.
    private func restoreAccessoryIfNoWindows(except closing: NSWindow? = nil) {
        let stillOpen = [addCharWindow, friendsWindow].compactMap { $0 }
            .filter { $0 !== closing && $0.isVisible }
        if stillOpen.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    func windowWillClose(_ notification: Notification) {
        let w = notification.object as? NSWindow
        if w === addCharWindow || w === friendsWindow {
            restoreAccessoryIfNoWindows(except: w)   // `w` still reports isVisible==true here
        }
    }
    @objc private func menuCheckUpdates() { updater.checkForUpdates(nil) }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    /// "Reset Pat… (start over)" — removes you + all your friendships from the server (friends see you
    /// vanish), forgets this Mac's identity + setup, and relaunches into a fresh onboarding. Confirmed
    /// first because it's irreversible.
    @objc private func menuReset() {
        let alert = NSAlert()
        alert.messageText = "Reset Digital Pat?"
        alert.informativeText = "This removes you and all your friendships, forgets your name and setup on this Mac, and starts you over with a brand-new pet. Your friends will see you disappear. This can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let resp = alert.runModal()
        restoreAccessoryIfNoWindows()
        guard resp.rawValue == 1000 else { return }   // 1000 = alertFirstButtonResponse ("Reset")
        Task { @MainActor in
            await FriendStore.shared.resetAccount()
            if let bid = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bid)   // name, character, positions, cursor mode
            }
            relaunchApp()
        }
    }

    /// Quit and reopen a fresh instance (used after a reset). The detached `open` waits for us to exit
    /// so the single-instance guard lets the new copy through.
    private func relaunchApp() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: pet panel

    private func setupPetPanel() {
        let size = NSSize(width: 130, height: 92)
        petPanel = PetPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        petPanel.isOpaque = false
        petPanel.backgroundColor = .clear
        petPanel.hasShadow = false
        petPanel.level = .floating
        petPanel.isMovable = false
        petPanel.hidesOnDeactivate = false
        petPanel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                       .fullScreenAuxiliary, .ignoresCycle]

        let cat = CatView(
            state: state,
            anim: state.animator,
            onPat: { [weak self] in self?.state.pat() },
            onDragChanged: { [weak self] t in self?.dragPet(by: t) },
            onDragEnded: { [weak self] in self?.endDragPet() }
        )
        let host = NSHostingView(rootView: cat)
        host.frame = petPanel.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        petPanel.contentView = host
        petPanel.onRightClick = { [weak self] ev in self?.showPetMenu(ev) }   // right-click MY pet → controls

        positionPet(size: size)
        petPanel.orderFrontRegardless()

        roamer = Roamer(panel: petPanel, state: state)
        roamer?.setCalm(!keepRoaming)          // default: not roaming (calm); cursor still moves her
        roamer?.start()

        // Cursor reaction (Attract/Push/Neutral) — the SAME engine friend pets use. ALWAYS active
        // (Pat is always free-flowing via the cursor); only yields while dragging, mid-roam-glide,
        // or hidden.
        reactor = CursorReactor(panel: petPanel, state: state, isEnabled: { [weak self] in
            guard let self else { return false }
            return !self.dragging && !(self.roamer?.isGliding ?? false) && !self.state.isHidden
        })
        reactor?.onActiveMove = { [weak self] in self?.roamer?.noteCursorReaction() }
        // Restore the saved mode — but Chipkoo is a LATCH whose only exit is a pat, so it must never
        // resurrect on launch (you'd relaunch to a pet glued to the cursor with no obvious off-switch).
        // Attract/Push still persist. The reactor OBSERVES state.cursorMode, so just write it.
        let saved = CursorMode.from(UserDefaults.standard.string(forKey: "pat.me.cursorMode"))
        state.cursorMode = (saved == .chipkoo ? .neutral : saved)
        reactor?.start()

        // Roaming would wander a clung pet away from the cursor; while Chipkoo is on, force calm, and
        // restore the user's Keep-roaming preference when it's released. (Single source: observe mode.)
        modeObserver = state.$cursorMode.sink { [weak self] m in
            guard let self else { return }
            self.roamer?.setCalm(m == .chipkoo ? true : !self.keepRoaming)
        }
        // When a friend's pat asks me to release my pet, clear my own Chipkoo (epoch-checked → no-op
        // if it's stale or I've already moved on).
        FriendStore.shared.onMyPetClearRequested = { [weak self] epoch in self?.state.clearChipkoo(epoch: epoch) }

        // Keep Pat in the top-right if the display layout changes.
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func setTopRight(size: NSSize) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        petPanel.setFrameOrigin(NSPoint(x: vf.maxX - size.width - 20,
                                        y: vf.maxY - size.height - 8))
    }

    private func positionPet(size: NSSize) {
        // Start where Pat last was (if still on a screen); otherwise default to the top-right.
        if let saved = UserDefaults.standard.string(forKey: posKey) {
            let pt = NSPointFromString(saved)
            if visibleSomewhere(origin: pt, size: size) {
                petPanel.setFrameOrigin(pt)
                return
            }
        }
        setTopRight(size: size)
    }

    private func visibleSomewhere(origin: NSPoint, size: NSSize) -> Bool {
        let rect = NSRect(origin: origin, size: size)
        return NSScreen.screens.contains { $0.frame.intersects(rect) }
    }

    /// Smooth drag: position the window from the GLOBAL mouse location and a fixed
    /// grab offset, so moving the window never shifts the gesture's reference frame
    /// (that feedback loop was the source of the jitter). Plain move — no walk, no
    /// sprite change. The kitten just goes where you put it.
    private func dragPet(by t: CGSize) {
        let mouse = NSEvent.mouseLocation
        if !dragging {
            dragging = true
            roamer?.dragging = true   // suspend roaming + cancel any glide
            let o = petPanel.frame.origin
            grabOffset = CGSize(width: mouse.x - o.x, height: mouse.y - o.y)
        }
        petPanel.setFrameOrigin(NSPoint(x: mouse.x - grabOffset.width,
                                        y: mouse.y - grabOffset.height))
    }

    private func endDragPet() {
        dragging = false
        roamer?.dragging = false
        UserDefaults.standard.set(NSStringFromPoint(petPanel.frame.origin), forKey: posKey)
        reactor?.kick()   // re-close the cling gap even on a still cursor (e.g. dropped while Chipkoo)
    }

    private func toggleHidden() {
        state.isHidden.toggle()
        if state.isHidden { petPanel.orderOut(nil) }
        else { petPanel.orderFrontRegardless(); reactor?.kick() }   // resume clinging on a still cursor
    }

    /// Quitting while clinging: untrack presence so friends' copies un-cling at once (not after the
    /// 120s staleness fallback). Bounded so quit never hangs on the network.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        var replied = false
        let reply = { if !replied { replied = true; NSApp.reply(toApplicationShouldTerminate: true) } }
        Task { @MainActor in await FriendStore.shared.untrackAll(); reply() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { reply() }
        return .terminateLater
    }

    // MARK: launch at login

    private var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func toggleLaunchAtLogin() {
        do {
            if launchesAtLogin { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            NSLog("Digital Pat: launch-at-login toggle failed: \(error)")
        }
    }
}
