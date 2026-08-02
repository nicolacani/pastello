import AppKit
import Combine
import CryptoKit

final class ClipboardStore: ObservableObject {
    static let maxUnpinned = 50
    static let maxImages = 30
    static let maxTextLength = 100_000
    static let thumbMaxPixel: CGFloat = 320

    @Published private(set) var items: [ClipItem] = []
    @Published var search = "" { didSet { resetSelection() } }
    @Published var selectedID: UUID?
    @Published var multiSelection: Set<UUID> = []
    // Bumped only by keyboard navigation: hover must never scroll the list.
    @Published var scrollTick = 0

    private var lastChangeCount: Int
    private var ignoreChangeCount = -1
    private var timer: Timer?
    private var saveWork: DispatchWorkItem?
    private var lastSaveDate = Date()
    private let thumbCache = NSCache<NSString, NSImage>()
    private var pendingThumbs = Set<String>()
    // Serial queue for all disk I/O: JSON encoding/writes, PNGs, thumbnails, deletions.
    // Serial ordering guarantees a deletion enqueued after a write always follows it.
    private let ioQueue = DispatchQueue(label: "it.foolica.pastello.io", qos: .utility)

    let dirURL: URL
    let imgDirURL: URL
    private var historyURL: URL { dirURL.appendingPathComponent("history.json") }

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dirURL = base.appendingPathComponent("Pastello", isDirectory: true)
        imgDirURL = dirURL.appendingPathComponent("imgs", isDirectory: true)
        try? FileManager.default.createDirectory(at: imgDirURL, withIntermediateDirectories: true)
        thumbCache.countLimit = 60
        load()
    }

    // MARK: - Clipboard watching

    func start() {
        let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        // Writes made by Pastello itself: don't re-ingest them.
        if count == ignoreChangeCount { return }
        ingest(pb)
    }

    private func ingest(_ pb: NSPasteboard) {
        let typeIDs = (pb.types ?? []).map { $0.rawValue }
        // nspasteboard.org convention: password managers mark sensitive/transient data.
        if typeIDs.contains("org.nspasteboard.ConcealedType") || typeIDs.contains("org.nspasteboard.TransientType") {
            return
        }

        let src = NSWorkspace.shared.frontmostApplication
        let appName = src?.localizedName
        let appID = src?.bundleIdentifier
        if appID != nil && appID == Bundle.main.bundleIdentifier { return }

        // 1. Copied files (e.g. from Finder)
        if let objs = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]),
           let urls = objs as? [URL], !urls.isEmpty {
            let paths = urls.map(\.path).joined(separator: "\n")
            add(ClipItem(id: UUID(), kind: .file, text: paths, imageFile: nil, imageHash: nil,
                         imageWidth: nil, imageHeight: nil, date: Date(), pinned: false,
                         appName: appName, appBundleID: appID))
            return
        }

        // 2. Images (screenshots, copies from browsers/editors)
        let pngData = pb.data(forType: .png)
        if let rawData = pngData ?? pb.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: rawData) {
            let hash = SHA256.hash(data: rawData).prefix(12).map { String(format: "%02x", $0) }.joined()
            var item = ClipItem(id: UUID(), kind: .image, text: nil, imageFile: nil, imageHash: hash,
                                imageWidth: rep.pixelsWide, imageHeight: rep.pixelsHigh, date: Date(),
                                pinned: false, appName: appName, appBundleID: appID)
            if !items.contains(where: { $0.matchesContent(of: item) }) {
                let name = item.id.uuidString + ".png"
                item.imageFile = name
                let itemID = item.id
                let fileURL = imgDirURL.appendingPathComponent(name)
                let thumbURL = imgDirURL.appendingPathComponent(name + ".thumb.png")
                let isPNG = pngData != nil
                // Encoding/decoding and writes off the main thread: a 5K screenshot
                // must not freeze the popover and hotkey. If the data is already PNG
                // it's written as-is, without recompressing.
                ioQueue.async { [weak self] in
                    let fileData = isPNG ? rawData : rep.representation(using: .png, properties: [:])
                    let wrote = fileData.map { (try? $0.write(to: fileURL)) != nil } ?? false
                    var thumb: NSImage?
                    if wrote, let t = Self.makeThumb(from: rep) {
                        if let d = t.pngData { try? d.write(to: thumbURL) }
                        thumb = t.image
                    }
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if !wrote {
                            // Write failed (e.g. disk full): no dangling reference.
                            if let i = self.items.firstIndex(where: { $0.id == itemID }) {
                                self.items[i].imageFile = nil
                            }
                        } else if let thumb {
                            self.thumbCache.setObject(thumb, forKey: name as NSString)
                            self.objectWillChange.send()
                        }
                    }
                }
            }
            add(item)
            return
        }

        // 3. Text
        if let s = pb.string(forType: .string) {
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let capped = s.count > Self.maxTextLength ? String(s.prefix(Self.maxTextLength)) : s
            add(ClipItem(id: UUID(), kind: .text, text: capped, imageFile: nil, imageHash: nil,
                         imageWidth: nil, imageHeight: nil, date: Date(), pinned: false,
                         appName: appName, appBundleID: appID))
        }
    }

    private func add(_ newItem: ClipItem) {
        var item = newItem
        if let idx = items.firstIndex(where: { $0.matchesContent(of: item) }) {
            let old = items.remove(at: idx)
            item.pinned = old.pinned
            item.label = old.label
            if item.kind == .image { item.imageFile = old.imageFile }
        }
        items.insert(item, at: 0)
        trim()
        scheduleSave()
    }

    private func trim() {
        var unpinned = items.filter { !$0.pinned }.count
        if unpinned > Self.maxUnpinned {
            for i in stride(from: items.count - 1, through: 0, by: -1) {
                if unpinned <= Self.maxUnpinned { break }
                if !items[i].pinned {
                    removeFiles(of: items[i])
                    items.remove(at: i)
                    unpinned -= 1
                }
            }
        }
        var imgCount = items.filter { $0.kind == .image && !$0.pinned }.count
        if imgCount > Self.maxImages {
            for i in stride(from: items.count - 1, through: 0, by: -1) {
                if imgCount <= Self.maxImages { break }
                if items[i].kind == .image, !items[i].pinned {
                    removeFiles(of: items[i])
                    items.remove(at: i)
                    imgCount -= 1
                }
            }
        }
    }

    // MARK: - Visible list and selection

    var visibleItems: [ClipItem] {
        let q = search.trimmingCharacters(in: .whitespaces)
        // localizedStandardContains: allocation-free, case/diacritic-insensitive
        // (4x faster than lowercased().contains on long texts).
        let filtered = q.isEmpty ? items : items.filter {
            ($0.text?.localizedStandardContains(q) ?? false)
                || ($0.label?.localizedStandardContains(q) ?? false)
                || ($0.appName?.localizedStandardContains(q) ?? false)
                || ($0.kind == .image && "image".localizedStandardContains(q))
        }
        return filtered.filter(\.pinned) + filtered.filter { !$0.pinned }
    }

    var selectedItem: ClipItem? {
        visibleItems.first { $0.id == selectedID } ?? visibleItems.first
    }

    func resetSelection() {
        selectedID = visibleItems.first?.id
        scrollTick &+= 1
    }

    func moveSelection(_ delta: Int) {
        let vis = visibleItems
        guard !vis.isEmpty else { return }
        if let cur = selectedID, let idx = vis.firstIndex(where: { $0.id == cur }) {
            selectedID = vis[min(max(idx + delta, 0), vis.count - 1)].id
        } else {
            selectedID = vis.first?.id
        }
        scrollTick &+= 1
    }

    // MARK: - Actions

    func copyToPasteboard(_ item: ClipItem, textOverride: String? = nil) {
        let pb = NSPasteboard.general
        switch item.kind {
        case .text:
            pb.clearContents()
            pb.setString(textOverride ?? item.text ?? "", forType: .string)
        case .file:
            let urls = (item.text ?? "").split(separator: "\n").map { NSURL(fileURLWithPath: String($0)) }
            pb.clearContents()
            pb.writeObjects(urls)
        case .image:
            // Load first, then clear: if the file is missing, the user's
            // previous clipboard contents aren't destroyed.
            guard let f = item.imageFile,
                  let img = NSImage(contentsOf: imgDirURL.appendingPathComponent(f)) else {
                NSSound.beep()
                return
            }
            pb.clearContents()
            pb.writeObjects([img])
        }
        ignoreChangeCount = pb.changeCount
    }

    /// Joins the selected text items (oldest to newest), copies them to the
    /// pasteboard and also saves them as a new history item.
    func copyCombined() -> Bool {
        let sel = visibleItems.filter { multiSelection.contains($0.id) && $0.kind == .text }
        guard sel.count >= 2 else { return false }
        let combined = sel.reversed().map { ($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(combined, forType: .string)
        ignoreChangeCount = pb.changeCount
        multiSelection.removeAll()
        add(ClipItem(id: UUID(), kind: .text, text: combined, imageFile: nil, imageHash: nil,
                     imageWidth: nil, imageHeight: nil, date: Date(), pinned: false,
                     appName: "Pastello", appBundleID: Bundle.main.bundleIdentifier))
        return true
    }

    func setLabel(_ item: ClipItem, _ label: String) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].label = label.isEmpty ? nil : label
        scheduleSave()
    }

    func togglePin(_ item: ClipItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].pinned.toggle()
        scheduleSave()
    }

    func delete(_ item: ClipItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        removeFiles(of: items[i])
        items.remove(at: i)
        multiSelection.remove(item.id)
        if selectedID == item.id { resetSelection() }
        scheduleSave()
    }

    func clear(keepPinned: Bool) {
        for item in items where !(keepPinned && item.pinned) {
            removeFiles(of: item)
        }
        items = keepPinned ? items.filter(\.pinned) : []
        multiSelection.removeAll()
        resetSelection()
        scheduleSave()
    }

    // MARK: - Thumbnails

    /// Returns a scaled-down thumbnail (never the full-resolution image:
    /// a decoded 5K screenshot would take tens of MB for a 72pt row).
    func thumbnail(for item: ClipItem) -> NSImage? {
        guard item.kind == .image, let f = item.imageFile else { return nil }
        let key = f as NSString
        if let cached = thumbCache.object(forKey: key) { return cached }
        let thumbURL = imgDirURL.appendingPathComponent(f + ".thumb.png")
        if let img = NSImage(contentsOf: thumbURL) {
            thumbCache.setObject(img, forKey: key)
            return img
        }
        // Thumbnail missing (history predating thumbnails): generate it in the
        // background; the row updates when done via objectWillChange.
        if !pendingThumbs.contains(f) {
            pendingThumbs.insert(f)
            let fullURL = imgDirURL.appendingPathComponent(f)
            ioQueue.async { [weak self] in
                var made: NSImage?
                if let data = try? Data(contentsOf: fullURL),
                   let rep = NSBitmapImageRep(data: data),
                   let t = Self.makeThumb(from: rep) {
                    if let d = t.pngData { try? d.write(to: thumbURL) }
                    made = t.image
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.pendingThumbs.remove(f)
                    if let made {
                        self.thumbCache.setObject(made, forKey: key)
                        self.objectWillChange.send()
                    }
                }
            }
        }
        return nil
    }

    private static func makeThumb(from rep: NSBitmapImageRep) -> (image: NSImage, pngData: Data?)? {
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        guard w > 0, h > 0 else { return nil }
        let scale = min(1, thumbMaxPixel / max(w, h))
        let tw = max(1, Int(w * scale)), th = max(1, Int(h * scale))
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: tw, pixelsHigh: th,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        out.size = NSSize(width: tw, height: th)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        rep.draw(in: NSRect(x: 0, y: 0, width: tw, height: th))
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: out.size)
        img.addRepresentation(out)
        return (img, out.representation(using: .png, properties: [:]))
    }

    private func removeFiles(of item: ClipItem) {
        guard let f = item.imageFile else { return }
        let stillUsed = items.contains { $0.id != item.id && $0.imageFile == f }
        guard !stillUsed else { return }
        thumbCache.removeObject(forKey: f as NSString)
        let full = imgDirURL.appendingPathComponent(f)
        let thumb = imgDirURL.appendingPathComponent(f + ".thumb.png")
        ioQueue.async {
            try? FileManager.default.removeItem(at: full)
            try? FileManager.default.removeItem(at: thumb)
        }
    }

    // MARK: - Persistence

    private func load() {
        let url = historyURL
        let imgDir = imgDirURL
        ioQueue.async { [weak self] in
            guard let data = try? Data(contentsOf: url) else { return }
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            guard let loaded = try? dec.decode([ClipItem].self, from: data) else {
                // Corrupt file: keep a copy and do NOT touch the images;
                // a sweep against an empty list would delete them all.
                let bak = url.appendingPathExtension("bak")
                try? FileManager.default.removeItem(at: bak)
                try? FileManager.default.copyItem(at: url, to: bak)
                return
            }
            // Orphan cleanup only after a successful decode.
            var referenced = Set<String>()
            for f in loaded.compactMap(\.imageFile) {
                referenced.insert(f)
                referenced.insert(f + ".thumb.png")
            }
            if let files = try? FileManager.default.contentsOfDirectory(atPath: imgDir.path) {
                for f in files where !referenced.contains(f) {
                    try? FileManager.default.removeItem(at: imgDir.appendingPathComponent(f))
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                // Any copies captured while loading stay on top.
                self.items += loaded
                self.resetSelection()
            }
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        // Debounce with a max latency: a burst of rapid copies can't postpone
        // the save forever (data loss on crash/force-quit).
        if Date().timeIntervalSince(lastSaveDate) > 5 {
            saveNow()
            return
        }
        let w = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: w)
    }

    func saveNow() {
        lastSaveDate = Date()
        let snapshot = items
        let url = historyURL
        ioQueue.async {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? enc.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Synchronous save for app exit.
    func flushSync() {
        saveWork?.cancel()
        saveNow()
        ioQueue.sync {}
    }
}
