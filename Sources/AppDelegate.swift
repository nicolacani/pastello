import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

extension Notification.Name {
    static let pastelloPopoverOpened = Notification.Name("PastelloPopoverOpened")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let store = ClipboardStore()
    let updater = UpdateChecker()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var hotKey: HotKey?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var activityToken: NSObjectProtocol?
    private var lastPopoverClose = Date.distantPast
    private var queueHotKey: HotKey?
    private var queuePanel: NSPanel?
    private var previewPanel: NSPanel?
    private var cancellables = Set<AnyCancellable>()

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

        hotKey = HotKey(id: 1, keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.togglePopover()
        }
        // ⌥⌘V: pastes the next item of the paste queue.
        queueHotKey = HotKey(id: 2, keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            self?.advanceQueue()
        }

        // Dimmed icon while capture is paused.
        store.$isPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paused in self?.statusItem.button?.appearsDisabled = paused }
            .store(in: &cancellables)
        // Queue HUD: appears when it starts, disappears shortly after the last paste.
        store.$pasteQueue
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queue in
                guard let self else { return }
                if queue.isEmpty { self.scheduleQueueHUDClose() } else { self.showQueueHUD() }
            }
            .store(in: &cancellables)

        // Update check: shortly after launch, then at most once a day.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.updater.checkAutomatically()
        }
        let updateTimer = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.updater.checkAutomatically()
        }
        RunLoop.main.add(updateTimer, forMode: .common)

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didOnboard") {
            defaults.set(true, forKey: "didOnboard")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.showPopover() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flushSync()
    }

    // pastello://add?text=…&label=…&source=… for dictation apps and scripts:
    // the text enters the history without touching the system clipboard.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "pastello" {
            guard url.host == "add" || url.host == "capture",
                  let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let text = comps.queryItems?.first(where: { $0.name == "text" })?.value,
                  !text.isEmpty else { continue }
            let label = comps.queryItems?.first(where: { $0.name == "label" })?.value
            let source = comps.queryItems?.first(where: { $0.name == "source" })?.value
            store.addExternal(text: text, label: label, source: source)
        }
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
        store.typeFilter = nil
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

    func popoverDidShow(_ notification: Notification) {
        // Invisible to screenshots, recordings and screen sharing.
        popover.contentViewController?.view.window?.sharingType = .none
    }

    func popoverDidClose(_ notification: Notification) {
        removeKeyMonitor()
        closePreview()
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
            if previewPanel?.isVisible == true {
                closePreview()
            } else if !store.search.isEmpty {
                store.search = ""
            } else if store.typeFilter != nil {
                store.typeFilter = nil
            } else {
                closePopover()
            }
            return true
        case 49 where store.search.isEmpty: // space = preview, like in the Finder
            togglePreview()
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

    // MARK: - Paste queue

    func startSequentialPaste() {
        guard store.startQueue() else { return }
        closePopover()
        previousApp?.activate(options: [])
    }

    private func advanceQueue() {
        guard store.dequeueNext() != nil else { return }
        if AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self.sendCmdV() }
        }
    }

    private func showQueueHUD() {
        if queuePanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 56),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.sharingType = .none
            panel.ignoresMouseEvents = false
            panel.contentView = NSHostingView(rootView: QueueHUDView(store: store) { [weak self] in
                self?.store.cancelQueue()
            })
            queuePanel = panel
        }
        if let screen = NSScreen.main, let panel = queuePanel {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.minY + 70))
            panel.orderFrontRegardless()
        }
    }

    private func scheduleQueueHUDClose() {
        guard queuePanel != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.store.pasteQueue.isEmpty else { return }
            self.queuePanel?.orderOut(nil)
        }
    }

    // MARK: - Preview (space bar)

    func togglePreview() {
        if previewPanel?.isVisible == true {
            closePreview()
            return
        }
        guard store.selectedItem != nil else { return }
        if previewPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 500),
                                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.title = "Preview"
            panel.titlebarAppearsTransparent = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.sharingType = .none
            panel.contentView = NSHostingView(rootView: PreviewView(store: store))
            panel.center()
            previewPanel = panel
        }
        // The panel never becomes key: the arrows keep navigating the list in
        // the popover and the preview follows the selection, like Quick Look in the Finder.
        previewPanel?.orderFrontRegardless()
    }

    func closePreview() {
        previewPanel?.orderOut(nil)
    }

    func previewItem(_ item: ClipItem) {
        store.selectedID = item.id
        if previewPanel?.isVisible != true { togglePreview() }
    }

    // MARK: - OCR and exclusions

    func copyOCRText(_ item: ClipItem) {
        guard let text = item.ocrText, !text.isEmpty else { return }
        // Enters the history as new text, attributed to the image's app.
        store.addExternal(text: text, label: nil, source: item.appName)
        if let newItem = store.items.first {
            store.copyToPasteboard(newItem)
        }
        closePopover()
    }

    func excludeApp(of item: ClipItem) {
        guard let id = item.appBundleID else { return }
        store.excludedApps.insert(id)
    }

    func addExcludedAppViaPanel() {
        closePopover()
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.message = "Choose apps whose copies should not be recorded"
        panel.prompt = "Exclude"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let bundleID = Bundle(url: url)?.bundleIdentifier {
                    store.excludedApps.insert(bundleID)
                }
            }
        }
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
        // An entry created by an older version (hash-based signature) stays
        // "dead" even after unchecking and rechecking the box: macOS re-enables
        // the old entry without refreshing its requirement. It has to be deleted
        // and recreated: the reset touches only Pastello, it is a revocation and
        // grants nothing by itself.
        let reset = Process()
        reset.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        reset.arguments = ["reset", "Accessibility", "it.foolica.pastello"]
        try? reset.run()
        reset.waitUntilExit()
        // Then the clean system dialog; if the permission still is not there
        // after a few seconds, show the guide to fix things by hand.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, !AXIsProcessTrusted() else { return }
            self.closePopover()
            let a = NSAlert()
            a.messageText = "Enable auto-paste"
            a.informativeText = """
            In System Settings → Privacy & Security → Accessibility:

            • if Pastello isn't listed, add it with "+" picking it from /Applications
            • if it's already there but not working, select it, remove it with "−" and add it back with "+"

            Starting with this version the permission survives updates: this is the last time you'll need to do it.
            """
            a.addButton(withTitle: "Open Settings")
            a.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            if a.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
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
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        a.messageText = "Pastello \(version)"
        a.informativeText = """
        Your multi-clipboard for Mac.

        ⇧⌘V opens the history anywhere
        ↩ pastes, Space previews, ⌘1…⌘9 paste instantly
        ⌘click multi-select: paste together or sequentially (⌥⌘V)
        ⌘P pins to top, ⌘⌫ deletes
        Images are searchable thanks to local OCR

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

        let pause = NSMenuItem(title: "Pause capture", action: #selector(menuPause), keyEquivalent: "")
        pause.target = self
        pause.state = store.isPaused ? .on : .off
        menu.addItem(pause)
        let ignoreNext = NSMenuItem(title: "Ignore next copy", action: #selector(menuIgnoreNext), keyEquivalent: "")
        ignoreNext.target = self
        menu.addItem(ignoreNext)
        if !store.pasteQueue.isEmpty {
            let cancelQueue = NSMenuItem(title: "Cancel paste queue", action: #selector(menuCancelQueue), keyEquivalent: "")
            cancelQueue.target = self
            menu.addItem(cancelQueue)
        }
        menu.addItem(.separator())

        let clearKeep = NSMenuItem(title: "Clear (keep pinned)", action: #selector(menuClearKeep), keyEquivalent: "")
        clearKeep.target = self
        menu.addItem(clearKeep)
        let clearAll = NSMenuItem(title: "Clear everything…", action: #selector(menuClearAll), keyEquivalent: "")
        clearAll.target = self
        menu.addItem(clearAll)
        menu.addItem(.separator())

        let updates = NSMenuItem(title: "Check for updates…", action: #selector(menuCheckUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)
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
    @objc private func menuPause() { store.isPaused.toggle() }
    @objc private func menuIgnoreNext() { store.ignoreNextCopy = true }
    @objc private func menuCancelQueue() { store.cancelQueue() }
    @objc private func menuCheckUpdates() { updater.check(userInitiated: true) }
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
            pasteSequential: { [weak self] in self?.startSequentialPaste() },
            copyOnly: { [weak self] item in self?.copyOnly(item) },
            rename: { [weak self] item in self?.renameItem(item) },
            preview: { [weak self] item in self?.previewItem(item) },
            copyOCR: { [weak self] item in self?.copyOCRText(item) },
            excludeApp: { [weak self] item in self?.excludeApp(of: item) },
            addExcludedApp: { [weak self] in self?.addExcludedAppViaPanel() },
            enableAutoPaste: { [weak self] in self?.requestAutoPaste() },
            autoPasteEnabled: { AXIsProcessTrusted() },
            toggleLogin: { [weak self] in self?.toggleLogin() },
            loginEnabled: { [weak self] in self?.loginEnabled ?? false },
            checkUpdates: { [weak self] in self?.updater.check(userInitiated: true) },
            clearKeepPinned: { [weak self] in self?.store.clear(keepPinned: true) },
            clearAll: { [weak self] in self?.clearAllWithConfirm() },
            about: { [weak self] in self?.showAbout() },
            quit: { NSApp.terminate(nil) }
        )
    }
}
