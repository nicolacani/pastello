import SwiftUI
import AppKit

struct PopoverActions {
    let paste: (ClipItem) -> Void
    let pasteTransformed: (ClipItem, @escaping (String) -> String) -> Void
    let pasteCombined: () -> Void
    let pasteSequential: () -> Void
    let copyOnly: (ClipItem) -> Void
    let rename: (ClipItem) -> Void
    let preview: (ClipItem) -> Void
    let copyOCR: (ClipItem) -> Void
    let excludeApp: (ClipItem) -> Void
    let addExcludedApp: () -> Void
    let enableAutoPaste: () -> Void
    let autoPasteEnabled: () -> Bool
    let toggleLogin: () -> Void
    let loginEnabled: () -> Bool
    let checkUpdates: () -> Void
    let clearKeepPinned: () -> Void
    let clearAll: () -> Void
    let about: () -> Void
    let quit: () -> Void
}

// "Stationery" palette: a single warm accent, the coral of the dot on the
// icon. Flat tints, zero gradients in the UI: the identity lives in the
// pastel-card badge tints and in native restraint, not in AI purples.
let accent = Color(red: 0.95, green: 0.42, blue: 0.22)
// Adaptive text variant: terracotta in light mode, light coral in dark mode.
let accentText = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 1.00, green: 0.60, blue: 0.44, alpha: 1)
        : NSColor(srgbRed: 0.70, green: 0.29, blue: 0.12, alpha: 1)
})
// Selection veil: barely perceptible coral, flat.
let selectionFill = Color(red: 0.95, green: 0.42, blue: 0.22).opacity(0.09)

/// Keycap-style key for the shortcuts shown in the interface.
struct KeyCap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundColor(.secondary)
            .padding(.horizontal, 4.5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 0.5)
            )
    }
}

struct HistoryView: View {
    @ObservedObject var store: ClipboardStore
    let actions: PopoverActions
    @FocusState private var searchFocused: Bool
    @State private var loginOn = false

    var body: some View {
        let vis = store.visibleItems
        VStack(spacing: 0) {
            header
            searchBar
            filterBar
            Divider().opacity(0.6)
            if vis.isEmpty {
                emptyState
            } else {
                list(vis)
            }
            Divider().opacity(0.6)
            // In multi-selection the footer gives way to the action bar:
            // two stacked strips would double the chrome right when focus is needed.
            if store.multiSelection.count >= 2 {
                multiBar
            } else {
                footer
            }
        }
        .frame(width: 396, height: 484)
        .onAppear {
            loginOn = actions.loginEnabled()
            DispatchQueue.main.async { searchFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pastelloPopoverOpened)) { _ in
            loginOn = actions.loginEnabled()
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            // Two template layers stacked: as in the app icon, the orange sits
            // on the clip alone and the board follows the text colour, so it
            // stays readable in dark mode too.
            ZStack {
                Image(nsImage: BrandIcon.statusImage(part: .board))
                    .renderingMode(.template)
                    .foregroundStyle(.primary)
                Image(nsImage: BrandIcon.statusImage(part: .clip))
                    .renderingMode(.template)
                    .foregroundStyle(accent)
            }
            Text("Pastello")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Spacer()
            Text("\(store.items.count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(Color.primary.opacity(0.055)))
                .foregroundColor(.secondary)
                .help("Items in history")
            gearMenu
        }
        .padding(.horizontal, 13)
        .padding(.top, 11)
        .padding(.bottom, 7)
    }

    private var gearMenu: some View {
        Menu {
            if actions.autoPasteEnabled() {
                Text("Auto-paste active ✓")
            } else {
                Button("Enable auto-paste…") { actions.enableAutoPaste() }
            }
            Toggle("Launch at login", isOn: Binding(
                get: { loginOn },
                set: { _ in
                    actions.toggleLogin()
                    loginOn = actions.loginEnabled()
                }
            ))
            Toggle("Capture dictation", isOn: $store.captureTransient)
                .help("Also record transient texts pasted by dictation apps (Myna, Wispr Flow…)")
            Toggle("Dictation stays on the clipboard", isOn: $store.keepDictationOnClipboard)
                .help("After a dictation, ⌘V pastes the dictated text even if the app restored the previous clipboard")
            Divider()
            Toggle("Pause capture", isOn: $store.isPaused)
            Button("Ignore next copy") { store.ignoreNextCopy = true }
            Menu("History limit") {
                ForEach([25, 50, 100], id: \.self) { n in
                    Button {
                        store.historyLimit = n
                    } label: {
                        if store.historyLimit == n {
                            Label("\(n) items", systemImage: "checkmark")
                        } else {
                            Text("\(n) items")
                        }
                    }
                }
            }
            Menu("Excluded apps") {
                ForEach(store.excludedApps.sorted(), id: \.self) { bundleID in
                    Button("Re-allow \(Self.appDisplayName(bundleID))") {
                        store.excludedApps.remove(bundleID)
                    }
                }
                if !store.excludedApps.isEmpty { Divider() }
                Button("Add app…") { actions.addExcludedApp() }
            }
            Divider()
            Button("Delete last 5 minutes") { store.deleteRecent(minutes: 5) }
            Button("Clear (keep pinned)") { actions.clearKeepPinned() }
            Button("Clear everything…") { actions.clearAll() }
            Divider()
            Button("Check for updates…") { actions.checkUpdates() }
            Button("About Pastello") { actions.about() }
            Button("Quit Pastello") { actions.quit() }
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24)
    }

    // MARK: - Search and filters

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(searchFocused ? accentText : .secondary)
            TextField("Search your clips…", text: $store.search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
            if !store.search.isEmpty {
                Button {
                    store.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6.5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(searchFocused ? accent.opacity(0.55) : Color.primary.opacity(0.06),
                              lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: searchFocused)
        .padding(.horizontal, 11)
        .padding(.bottom, 7)
    }

    private var filterBar: some View {
        HStack(spacing: 5) {
            chip(nil, "All")
            ForEach(TypeFilter.allCases, id: \.self) { f in
                chip(f, f.rawValue)
            }
            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.bottom, 8)
    }

    private func chip(_ filter: TypeFilter?, _ title: String) -> some View {
        let active = store.typeFilter == filter
        return Button {
            store.typeFilter = filter
            store.resetSelection()
        } label: {
            Text(title)
                .font(.system(size: 10, weight: active ? .semibold : .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(
                    Capsule().fill(active ? accent.opacity(0.15) : Color.primary.opacity(0.055))
                )
                .foregroundColor(active ? accentText : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - List

    private func list(_ vis: [ClipItem]) -> some View {
        let firstUnpinned = vis.firstIndex { !$0.pinned }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(vis.enumerated()), id: \.element.id) { idx, item in
                        if idx == 0, item.pinned {
                            sectionHeader("Pinned", symbol: "pin.fill")
                        }
                        if let fu = firstUnpinned, idx == fu, fu > 0 {
                            sectionHeader("Recent", symbol: "clock")
                        }
                        ClipRow(store: store, item: item, index: idx,
                                isSelected: store.selectedID == item.id,
                                isMulti: store.multiSelection.contains(item.id),
                                actions: actions)
                            .id(item.id)
                    }
                }
                .padding(7)
            }
            // Scroll ONLY on keyboard navigation (scrollTick): anchoring to
            // selectedID would make the list jump under the cursor on every hover.
            .onChange(of: store.scrollTick) { _, _ in
                if let id = store.selectedID { proxy.scrollTo(id) }
            }
            // Fade on the bottom edge: rows slide away instead of being
            // cut off abruptly by the footer.
            .mask(
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 12)
                }
            )
        }
    }

    private func sectionHeader(_ title: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 7.5, weight: .semibold))
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.7)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 9)
        .padding(.top, 7)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle()
                    .fill(accent.opacity(0.10))
                    .frame(width: 76, height: 76)
                    .overlay(Circle().strokeBorder(accent.opacity(0.28), lineWidth: 1))
                Image(systemName: store.search.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                    .font(.system(size: 30, weight: .light))
                    .foregroundColor(accent)
            }
            if store.search.isEmpty {
                Text("Nothing here yet")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("Copy something with ⌘C and it will show up here.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 5) {
                    Text("Summon Pastello anywhere with")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    KeyCap(label: "⇧⌘V")
                }
            } else {
                Text("No results")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("Nothing contains “\(store.search)”.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Multi-selection bar and footer

    private var multiBar: some View {
        HStack(spacing: 8) {
            Text("\(store.multiSelection.count) selected")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Button("Paste together") { actions.pasteCombined() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(accent)
            Button("Sequentially") { actions.pasteSequential() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Queues the items: ⌥⌘V pastes the next one, field after field")
            Button {
                store.multiSelection.removeAll()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear selection")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(accent.opacity(0.06))
    }

    private var footer: some View {
        HStack(spacing: 9) {
            HStack(spacing: 4) {
                KeyCap(label: "↩")
                Text("paste").font(.system(size: 9.5)).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                KeyCap(label: "space")
                Text("preview").font(.system(size: 9.5)).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                KeyCap(label: "⌘1-9")
                Text("quick").font(.system(size: 9.5)).foregroundColor(.secondary)
            }
            HStack(spacing: 4) {
                KeyCap(label: "⌘click")
                Text("multi").font(.system(size: 9.5)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
    }
}

extension HistoryView {
    static func appDisplayName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }
}

// Floating HUD for the paste queue: shows the next item and how many remain.
struct QueueHUDView: View {
    @ObservedObject var store: ClipboardStore
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "list.number")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(accent)
            if let next = store.pasteQueue.first {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("Next: \(next.preview)")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("\(store.pasteQueue.count) queued")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        KeyCap(label: "⌥⌘V")
                        Text("pastes")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Queue finished ✓")
                    .font(.system(size: 12, weight: .medium))
            }
            Spacer(minLength: 4)
            Button {
                cancel()
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel the queue")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 400)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(accent.opacity(0.25), lineWidth: 1)
        )
    }
}

// Panel preview, Quick Look style: follows the list selection.
struct PreviewView: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        VStack(spacing: 0) {
            if let item = store.selectedItem {
                header(item)
                Divider()
                content(item)
            } else {
                Text("No item selected")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack(spacing: 4) {
                KeyCap(label: "space")
                Text("or").font(.system(size: 10)).foregroundColor(.secondary)
                KeyCap(label: "esc")
                Text("to close · arrows to browse")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 6)
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    private func header(_ item: ClipItem) -> some View {
        HStack(spacing: 8) {
            if let label = item.label {
                Image(systemName: "tag.fill").font(.system(size: 10)).foregroundColor(accent)
                Text(label).font(.system(size: 13, weight: .semibold))
            } else {
                Text(item.preview).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            Spacer()
            if let app = item.appName {
                Text(app).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .text:
            ScrollView {
                Text(item.text ?? "")
                    .font(.system(size: 13, design: item.flavor == .code ? .monospaced : .default))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        case .image:
            VStack(spacing: 0) {
                if let img = store.fullImage(for: item) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(10)
                } else {
                    Text("Image unavailable").foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let ocr = item.ocrText, !ocr.isEmpty {
                    Divider()
                    ScrollView {
                        Text(ocr)
                            .font(.system(size: 11))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(maxHeight: 110)
                }
            }
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach((item.text ?? "").split(separator: "\n").map(String.init), id: \.self) { path in
                        Label(path, systemImage: "doc")
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }
}

struct ClipRow: View {
    // No @ObservedObject here: the row receives values already computed by the
    // parent and uses the store only to call methods. Observing it would
    // re-evaluate ALL rows on every selection/hover change.
    let store: ClipboardStore
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let isMulti: Bool
    let actions: PopoverActions
    @State private var hovering = false

    private static let rel: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    var body: some View {
        // flavor/hexColor evaluated once per render, not in every subview.
        let flavor = item.flavor
        let swatch = item.hexColor
        HStack(alignment: .top, spacing: 9) {
            if isMulti {
                // Explicit binary indicator: in multi-selection what matters is
                // "in or out", not the content type.
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.13))
                        .frame(width: 28, height: 28)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(accent)
                }
            } else {
                badge(flavor: flavor, swatch: swatch)
            }
            VStack(alignment: .leading, spacing: 2.5) {
                if let label = item.label {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 7.5))
                            .foregroundColor(accent)
                        Text(label)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                content
                subtitleRow
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.vertical, 6.5)
        .padding(.horizontal, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowBackground)
        )
        .overlay {
            // A single selection language: veil + stroke in the brand accent,
            // stronger for multi-selection, thin for the keyboard.
            if isMulti {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(accent.opacity(0.65), lineWidth: 1.5)
            } else if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(accent.opacity(0.35), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { over in
            hovering = over
            if over { store.selectedID = item.id }
        }
        .onTapGesture {
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true, item.kind == .text {
                if isMulti {
                    store.multiSelection.remove(item.id)
                } else {
                    store.multiSelection.insert(item.id)
                }
            } else {
                actions.paste(item)
            }
        }
        .contextMenu { menuItems }
    }

    private var rowBackground: AnyShapeStyle {
        if isMulti || isSelected { return AnyShapeStyle(selectionFill) }
        if hovering { return AnyShapeStyle(Color.primary.opacity(0.05)) }
        return AnyShapeStyle(Color.clear)
    }

    // Entries shared between the context menu (right-click) and the "⋯" button.
    @ViewBuilder private var menuItems: some View {
        Button("Paste") { actions.paste(item) }
        Button("Copy without pasting") { actions.copyOnly(item) }
        Button("Preview (Space)") { actions.preview(item) }
        if item.kind == .image, item.ocrText?.isEmpty == false {
            Button("Copy text from image") { actions.copyOCR(item) }
        }
        Button(item.label == nil ? "Label…" : "Edit label…") { actions.rename(item) }
        if item.kind == .text {
            Menu("Paste as…") {
                Button("UPPERCASE") { actions.pasteTransformed(item) { $0.uppercased() } }
                Button("lowercase") { actions.pasteTransformed(item) { $0.lowercased() } }
                Button("On one line") {
                    actions.pasteTransformed(item) {
                        $0.components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")
                    }
                }
                Button("Without spaces (IBANs, codes)") {
                    actions.pasteTransformed(item) { $0.filter { !$0.isWhitespace } }
                }
            }
        }
        Button(item.pinned ? "Unpin" : "Pin to top") { store.togglePin(item) }
        Divider()
        if let app = item.appName, item.appBundleID != nil {
            Button("Exclude copies from \(app)") { actions.excludeApp(item) }
        }
        Button("Delete", role: .destructive) { store.delete(item) }
    }

    private var subtitleRow: some View {
        HStack(spacing: 4) {
            if let icon = store.appIcon(for: item.appBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 11, height: 11)
            }
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let a = item.appName, !a.isEmpty { parts.append(a) }
        // Under a minute "just now": cleaner than "0 sec ago" (or a spurious
        // future when the copy is a few milliseconds old).
        let age = Date().timeIntervalSince(item.date)
        parts.append(age < 60 ? "just now" : Self.rel.localizedString(for: item.date, relativeTo: Date()))
        if let info = item.charInfo { parts.append(info) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var content: some View {
        if item.kind == .image, let img = store.thumbnail(for: item) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 72, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        } else {
            Text(item.preview)
                .font(.system(size: 12))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func badgeColor(_ flavor: TextFlavor) -> Color {
        switch item.kind {
        case .image: return .teal
        case .file: return .orange
        case .text:
            switch flavor {
            case .url: return .blue
            case .email: return .green
            case .code: return .purple
            default: return .secondary
            }
        }
    }

    private func symbolName(_ flavor: TextFlavor) -> String {
        switch item.kind {
        case .image: return "photo"
        case .file: return "doc"
        case .text:
            switch flavor {
            case .url: return "link"
            case .email: return "at"
            case .code: return "chevron.left.forwardslash.chevron.right"
            default: return "text.alignleft"
            }
        }
    }

    private func badge(flavor: TextFlavor, swatch: NSColor?) -> some View {
        let base = badgeColor(flavor)
        return ZStack {
            // Flat pastel-card tint, no gradients.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(base.opacity(0.16))
                .frame(width: 28, height: 28)
            if let c = swatch {
                Circle()
                    .fill(Color(nsColor: c))
                    .frame(width: 15, height: 15)
                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
            } else {
                Image(systemName: symbolName(flavor))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(base)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        if hovering {
            HStack(spacing: 5) {
                Button {
                    store.togglePin(item)
                } label: {
                    Image(systemName: item.pinned ? "pin.slash" : "pin")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(item.pinned ? "Unpin" : "Pin to top (⌘P)")
                Button {
                    store.delete(item)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete (⌘⌫)")
                Menu {
                    menuItems
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More actions")
            }
        } else {
            HStack(spacing: 5) {
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundColor(accent)
                }
                // The keycap stays visible on pinned items too: ⌘1 is precisely
                // the shortcut of the most used item.
                if index < 9 {
                    KeyCap(label: "⌘\(index + 1)")
                        .opacity(0.6)
                }
            }
        }
    }
}
