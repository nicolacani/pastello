import Foundation

/// The "clean exit" signal read by the system watchdog.
///
/// The watchdog (`tools/watchdog.sh`, LaunchAgent `it.foolica.pastello.watchdog`)
/// reopens Pastello when it disappears from the menu bar without the user
/// having quit it. To tell a crash from a deliberate "Quit" it needs a mark
/// left by whoever exits in an orderly way: a crash never reaches
/// `applicationWillTerminate` and so never leaves one.
///
/// The file always lives at the real path, even with `PASTELLO_DATA_DIR` set:
/// it isn't history data, and it is the path the watchdog knows about.
enum CrashWatchdog {

    static var markerURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Pastello", isDirectory: true)
            .appendingPathComponent("clean-exit")
    }

    /// At launch the mark goes away: from here on, disappearing means a crash.
    static func appDidLaunch() {
        try? FileManager.default.removeItem(at: markerURL)
    }

    /// On an orderly exit (Quit from the menu, logout, restart, update) the mark
    /// stays behind and tells the watchdog not to reopen anything.
    static func appWillTerminate() {
        let dir = markerURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data().write(to: markerURL)
    }
}
