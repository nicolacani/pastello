import AppKit

// Update check through the public GitHub Releases API (no authentication,
// no dependencies). The Italian build (-D PASTELLO_ITA) only notifies: the
// public release is in English and the local copy updates from the Italian build.
final class UpdateChecker {
    private static let latestAPI = URL(string: "https://api.github.com/repos/nicolacani/pastello/releases/latest")!
    private var lastAutoCheck = Date.distantPast
    private var installing = false
    private var progressPanel: NSPanel?

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Silent check: at most once a day, speaks up only when there is news.
    func checkAutomatically() {
        guard Date().timeIntervalSince(lastAutoCheck) > 20 * 3600 else { return }
        lastAutoCheck = Date()
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        guard !installing else {
            if userInitiated { showInfo("Update already in progress", "Wait for it to finish.") }
            return
        }
        var req = URLRequest(url: Self.latestAPI)
        req.timeoutInterval = 30
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let data,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    if userInitiated { self.showError(error) }
                    return
                }
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let notes = (json["body"] as? String) ?? ""
                let pageURL = (json["html_url"] as? String).flatMap(URL.init(string:))
                let dmgURL = ((json["assets"] as? [[String: Any]]) ?? [])
                    .compactMap { $0["browser_download_url"] as? String }
                    .first { $0.hasSuffix(".dmg") }
                    .flatMap(URL.init(string:))

                if Self.isNewer(latest, than: self.currentVersion) {
                    if !userInitiated,
                       UserDefaults.standard.string(forKey: "skippedUpdate") == latest { return }
                    self.offerUpdate(version: latest, notes: notes, dmg: dmgURL,
                                     page: pageURL, userInitiated: userInitiated)
                } else if userInitiated {
                    self.showUpToDate()
                }
            }
        }.resume()
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let av = a.split(separator: ".").map { Int($0) ?? 0 }
        let bv = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Dialogs

    private func offerUpdate(version: String, notes: String, dmg: URL?, page: URL?, userInitiated: Bool) {
        let a = NSAlert()
        a.messageText = "Pastello \(version) is available"
        let shortNotes = String(notes.prefix(500))

        let close = "Later"
        let skip = "Skip this version"
        #if PASTELLO_ITA
        a.informativeText = """
        You have \(currentVersion). What's new:

        \(shortNotes)

        This Italian copy updates from the local build; the public GitHub release is in English.
        """
        let action = "Open the release page"
        #else
        a.informativeText = "You have \(currentVersion). What's new:\n\n\(shortNotes)"
        // The automatic install replaces /Applications/Pastello.app: if the app
        // runs from somewhere else, opening the release page is safer.
        let standardInstall = dmg != nil && Bundle.main.bundlePath == "/Applications/Pastello.app"
        let action = standardInstall ? "Download and install" : "Open the release page"
        #endif
        // In automatic checks the default button (Return) is the harmless one:
        // a Return "in flight" must not start a reinstall.
        let order = userInitiated ? [action, skip, close] : [close, action, skip]
        for title in order { a.addButton(withTitle: title) }
        NSApp.activate(ignoringOtherApps: true)
        let idx = a.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard idx >= 0, idx < order.count else { return }
        switch order[idx] {
        case "Download and install":
            if let dmg { downloadAndInstall(dmg, version: version) }
        case "Open the release page":
            if let page { NSWorkspace.shared.open(page) }
        case skip:
            UserDefaults.standard.set(version, forKey: "skippedUpdate")
        default:
            break
        }
    }

    private func showUpToDate() {
        let a = NSAlert()
        a.messageText = "Pastello is up to date"
        a.informativeText = "You already have the latest version (\(currentVersion))."
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    private func showError(_ error: Error?) {
        showInfo("Could not check for updates",
                 error?.localizedDescription ?? "Try again later.")
    }

    private func showInfo(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    // MARK: - Download and install (public build)

    // Dedicated session with a hard cap on the total download time: a
    // trickling connection must not block the updater forever.
    private static let downloadSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    private func downloadAndInstall(_ url: URL, version: String) {
        installing = true
        showProgress("Downloading Pastello \(version)…")
        Self.downloadSession.downloadTask(with: url) { [weak self] temp, response, error in
            guard let self else { return }
            guard let temp, (response as? HTTPURLResponse)?.statusCode == 200 else {
                DispatchQueue.main.async {
                    self.finishInstall()
                    self.showError(error)
                }
                return
            }
            // The URLSession temp file disappears on return: move it right away.
            let dmg = FileManager.default.temporaryDirectory
                .appendingPathComponent("Pastello-\(version).dmg")
            try? FileManager.default.removeItem(at: dmg)
            do {
                try FileManager.default.moveItem(at: temp, to: dmg)
            } catch {
                DispatchQueue.main.async {
                    self.finishInstall()
                    self.showError(error)
                }
                return
            }
            DispatchQueue.main.async { self.showProgress("Installing Pastello \(version)…") }
            DispatchQueue.global(qos: .userInitiated).async {
                self.installDMG(dmg, version: version)
            }
        }.resume()
    }

    private func installDMG(_ dmg: URL, version: String) {
        let mountDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastello-update-\(version)")
        try? FileManager.default.createDirectory(at: mountDir, withIntermediateDirectories: true)

        func fail(_ message: String) {
            _ = Self.run("/usr/bin/hdiutil", ["detach", mountDir.path, "-quiet", "-force"])
            DispatchQueue.main.async {
                self.finishInstall()
                let a = NSAlert()
                a.messageText = "Update failed"
                a.informativeText = message
                a.addButton(withTitle: "OK")
                NSApp.activate(ignoringOtherApps: true)
                a.runModal()
            }
        }

        // A mount left behind by a failed attempt would make the attach fail.
        _ = Self.run("/usr/bin/hdiutil", ["detach", mountDir.path, "-quiet", "-force"])
        guard Self.run("/usr/bin/hdiutil",
                       ["attach", dmg.path, "-nobrowse", "-readonly", "-quiet",
                        "-mountpoint", mountDir.path]) == 0 else {
            fail("Could not open the downloaded disk image.")
            return
        }
        let newApp = mountDir.appendingPathComponent("Pastello.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else {
            fail("The disk image does not contain Pastello.app.")
            return
        }

        // Copy to staging, then swap with renames: the destructive step is
        // near atomic and on error the previous Pastello is restored.
        // Never delete the installed app before the new copy is complete.
        let fm = FileManager.default
        let dest = URL(fileURLWithPath: "/Applications/Pastello.app")
        let staging = URL(fileURLWithPath: "/Applications/.Pastello-new.app")
        let backup = URL(fileURLWithPath: "/Applications/.Pastello-old.app")
        try? fm.removeItem(at: staging)
        guard Self.run("/usr/bin/ditto", [newApp.path, staging.path]) == 0 else {
            try? fm.removeItem(at: staging)
            fail("Could not copy the new version into /Applications.")
            return
        }
        _ = Self.run("/usr/bin/xattr", ["-cr", staging.path])
        try? fm.removeItem(at: backup)
        do {
            if fm.fileExists(atPath: dest.path) {
                try fm.moveItem(at: dest, to: backup)
            }
            try fm.moveItem(at: staging, to: dest)
            try? fm.removeItem(at: backup)
        } catch {
            // Restore the previous version if the swap stopped halfway.
            if !fm.fileExists(atPath: dest.path), fm.fileExists(atPath: backup.path) {
                try? fm.moveItem(at: backup, to: dest)
            }
            try? fm.removeItem(at: staging)
            fail("Could not replace the app in /Applications.")
            return
        }
        _ = Self.run("/usr/bin/hdiutil", ["detach", mountDir.path, "-quiet", "-force"])
        try? fm.removeItem(at: dmg)

        DispatchQueue.main.async {
            // A small external process waits for our exit and relaunches the app.
            let pid = ProcessInfo.processInfo.processIdentifier
            let script = "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"\(dest.path)\""
            let relauncher = Process()
            relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
            relauncher.arguments = ["-c", script]
            try? relauncher.run()
            NSApp.terminate(nil)
        }
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        do {
            try p.run()
        } catch {
            return -1
        }
        p.waitUntilExit()
        return p.terminationStatus
    }

    // MARK: - Status panel

    private func showProgress(_ text: String) {
        if progressPanel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 64),
                                styleMask: [.titled, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.title = "Update"
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.center()
            progressPanel = panel
        }
        let label = NSTextField(labelWithString: text)
        label.alignment = .center
        label.frame = NSRect(x: 10, y: 20, width: 300, height: 22)
        progressPanel?.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 64))
        progressPanel?.contentView?.addSubview(label)
        progressPanel?.orderFrontRegardless()
    }

    private func finishInstall() {
        installing = false
        progressPanel?.orderOut(nil)
    }
}
