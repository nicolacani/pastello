import AppKit
import SwiftUI
import Carbon.HIToolbox
import ApplicationServices
import ServiceManagement

extension Notification.Name {
    static let pastelloPopoverOpened = Notification.Name("PastelloPopoverOpened")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let store = ClipboardStore()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hotKey: HotKey?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var activityToken: NSObjectProtocol?
    private var lastPopoverClose = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Watching the clipboard")
        store.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            // Custom glyph consistent with the app icon; template so macOS
            // tints it on its own in light/dark mode.
            if let icon = Bundle.main.image(forResource: "MenuBarIcon") {
                icon.isTemplate = true
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pastello")
            }
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 470)
        popover.contentViewController = NSHostingController(rootView: HistoryView(store: store, actions: makeActions()))

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.togglePopover()
        }

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didOnboard") {
            defaults.set(true, forKey: "didOnboard")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.showPopover() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flushSync()
    }

    // MARK: - Status item and popover

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        if popover.isShown {
            closePopover()
        } else if Date().timeIntervalSince(lastPopoverClose) > 0.25 {
            // The transient popover already closes on the mouse-down of the icon click;
            // the action arrives on mouse-up, would see it closed and reopen it right away.
            // If it just closed, that click meant "close": don't reopen.
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        store.search = ""
        store.multiSelection.removeAll()
        store.resetSelection()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installKeyMonitor()
        NotificationCenter.default.post(name: .pastelloPopoverOpened, object: nil)
    }

    func closePopover() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        removeKeyMonitor()
        lastPopoverClose = Date()
    }

    // MARK: - Keyboard in the popover

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        let cmd = e.modifierFlags.contains(.command)
        switch e.keyCode {
        case 53: // esc
            if store.search.isEmpty { closePopover() } else { store.search = "" }
            return true
        case 36, 76: // return
            if let item = store.selectedItem { paste(item) }
            return true
        case 125: // down arrow
            store.moveSelection(1)
            return true
        case 126: // up arrow
            store.moveSelection(-1)
            return true
        case 51 where cmd: // ⌘⌫
            if let item = store.selectedItem { store.delete(item) }
            return true
        default:
            if cmd {
                // Digits by positional keycode (numpad included) with a character
                // fallback: works even on layouts where digits are shifted (AZERTY).
                if let n = Self.digitKeyCodes[e.keyCode] ?? e.charactersIgnoringModifiers.flatMap(Int.init),
                   (1...9).contains(n) {
                    let vis = store.visibleItems
                    if n <= vis.count { paste(vis[n - 1]) }
                    return true
                }
                // ⌘P by character, not by keycode: on Dvorak/Colemak the physical key moves.
                if e.charactersIgnoringModifiers?.lowercased() == "p" {
                    if let item = store.selectedItem { store.togglePin(item) }
                    return true
                }
            }
            return false
        }
    }

    private static let digitKeyCodes: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, // top row
        83: 1, 84: 2, 85: 3, 86: 4, 87: 5, 88: 6, 89: 7, 91: 8, 92: 9, // numpad
    ]

    // MARK: - Paste

    func paste(_ item: ClipItem, transform: ((String) -> String)? = nil) {
        var override: String?
        if let transform, item.kind == .text { override = transform(item.text ?? "") }
        store.copyToPasteboard(item, textOverride: override)
        finishPaste()
    }

    func pasteCombined() {
        guard store.copyCombined() else { return }
        finishPaste()
    }

    func copyOnly(_ item: ClipItem) {
        store.copyToPasteboard(item)
        closePopover()
    }

    func renameItem(_ item: ClipItem) {
        closePopover()
        let a = NSAlert()
        a.messageText = "Clip label"
        a.informativeText = "A recognizable label so you can find it instantly (leave empty to remove it)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = item.label ?? ""
        field.placeholderString = "e.g. Project X API key"
        a.accessoryView = field
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            store.setLabel(item, field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func finishPaste() {
        closePopover()
        guard let target = previousApp else { return }
        target.activate(options: [])
        if AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.sendCmdV() }
        }
    }

    private func sendCmdV() {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Settings

    func requestAutoPaste() {
        guard !AXIsProcessTrusted() else { return }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "axPrompted") {
            // First request: the system dialog goes straight to the right pane.
            defaults.set(true, forKey: "axPrompted")
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return
        }
        // Request already consumed: almost always means a "dead" checkbox after an
        // update (the ad-hoc signature changes and macOS ties the permission to the
        // specific version). Pastello has to be removed and re-added by hand.
        closePopover()
        let a = NSAlert()
        a.messageText = "Enable auto-paste"
        a.informativeText = """
        In System Settings → Privacy & Security → Accessibility:

        • if Pastello isn't listed, add it with "+" picking it from /Applications
        • if it's already there but not working, select it, remove it with "−" and add it back with "+"

        This happens after an app update: macOS ties the permission to the exact version installed.
        """
        a.addButton(withTitle: "Open Settings")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    var loginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func toggleLogin() {
        do {
            if loginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval {
                    // macOS wants the user's explicit approval in Login Items.
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            closePopover()
            let a = NSAlert()
            a.messageText = "Couldn't update launch at login"
            a.informativeText = error.localizedDescription
            a.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
    }

    func clearAllWithConfirm() {
        let a = NSAlert()
        a.messageText = "Clear the entire history?"
        a.informativeText = "Pinned items will be removed too."
        a.alertStyle = .warning
        a.addButton(withTitle: "Clear everything")
        a.addButton(withTitle: "Cancel")
        closePopover()
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            store.clear(keepPinned: false)
        }
    }

    func showAbout() {
        let a = NSAlert()
        a.messageText = "Pastello 1.1"
        a.informativeText = """
        Your multi-clipboard for Mac.

        ⇧⌘V opens the history anywhere
        ↩ pastes the selected item
        ⌘1…⌘9 paste instantly
        ⌘click selects multiple texts to paste together
        ⌘P pins to top, ⌘⌫ deletes

        Developed by Nicola Cani.
        """
        if let icon = NSApp.applicationIconImage { a.icon = icon }
        a.addButton(withTitle: "OK")
        closePopover()
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    // MARK: - Right-click menu on the icon

    private func showStatusMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Pastello  (⇧⌘V)", action: #selector(menuOpen), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        if AXIsProcessTrusted() {
            menu.addItem(NSMenuItem(title: "Auto-paste active ✓", action: nil, keyEquivalent: ""))
        } else {
            let ax = NSMenuItem(title: "Enable auto-paste…", action: #selector(menuAutoPaste), keyEquivalent: "")
            ax.target = self
            menu.addItem(ax)
        }
        let login = NSMenuItem(title: "Launch at login", action: #selector(menuLogin), keyEquivalent: "")
        login.target = self
        login.state = loginEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let clearKeep = NSMenuItem(title: "Clear (keep pinned)", action: #selector(menuClearKeep), keyEquivalent: "")
        clearKeep.target = self
        menu.addItem(clearKeep)
        let clearAll = NSMenuItem(title: "Clear everything…", action: #selector(menuClearAll), keyEquivalent: "")
        clearAll.target = self
        menu.addItem(clearAll)
        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Pastello", action: #selector(menuAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "Quit Pastello", action: #selector(menuQuit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuOpen() { showPopover() }
    @objc private func menuAutoPaste() { requestAutoPaste() }
    @objc private func menuLogin() { toggleLogin() }
    @objc private func menuClearKeep() { store.clear(keepPinned: true) }
    @objc private func menuClearAll() { clearAllWithConfirm() }
    @objc private func menuAbout() { showAbout() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - Actions for the view

    private func makeActions() -> PopoverActions {
        PopoverActions(
            paste: { [weak self] item in self?.paste(item) },
            pasteTransformed: { [weak self] item, t in self?.paste(item, transform: t) },
            pasteCombined: { [weak self] in self?.pasteCombined() },
            copyOnly: { [weak self] item in self?.copyOnly(item) },
            rename: { [weak self] item in self?.renameItem(item) },
            enableAutoPaste: { [weak self] in self?.requestAutoPaste() },
            autoPasteEnabled: { AXIsProcessTrusted() },
            toggleLogin: { [weak self] in self?.toggleLogin() },
            loginEnabled: { [weak self] in self?.loginEnabled ?? false },
            clearKeepPinned: { [weak self] in self?.store.clear(keepPinned: true) },
            clearAll: { [weak self] in self?.clearAllWithConfirm() },
            about: { [weak self] in self?.showAbout() },
            quit: { NSApp.terminate(nil) }
        )
    }
}
