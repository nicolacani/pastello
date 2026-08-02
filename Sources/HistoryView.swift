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

let brandPink = Color(red: 0.95, green: 0.36, blue: 0.63)
let brandViolet = Color(red: 0.49, green: 0.36, blue: 0.96)
let brandGradient = LinearGradient(colors: [brandPink, brandViolet],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)

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
            Divider()
            if vis.isEmpty {
                emptyState
            } else {
                list(vis)
            }
            if store.multiSelection.count >= 2 {
                multiBar
            }
            Divider()
            footer
        }
        .frame(width: 380, height: 470)
        .onAppear {
            loginOn = actions.loginEnabled()
            DispatchQueue.main.async { searchFocused = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pastelloPopoverOpened)) { _ in
            loginOn = actions.loginEnabled()
            DispatchQueue.main.async { searchFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            // Same glyph as the menu bar, tinted with the brand gradient.
            if let glyph = Bundle.main.image(forResource: "MenuBarIcon") {
                Image(nsImage: glyph)
                    .renderingMode(.template)
                    .foregroundStyle(brandGradient)
            } else {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(brandGradient)
            }
            Text("Pastello")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(brandGradient)
            Spacer()
            Text("\(store.items.count)")
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .foregroundColor(.secondary)
                .help("Items in history")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var filterBar: some View {
        HStack(spacing: 4) {
            chip(nil, "All")
            ForEach(TypeFilter.allCases, id: \.self) { f in
                chip(f, f.rawValue)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 7)
    }

    private func chip(_ filter: TypeFilter?, _ title: String) -> some View {
        let active = store.typeFilter == filter
        return Button {
            store.typeFilter = filter
            store.resetSelection()
        } label: {
            Text(title)
                .font(.system(size: 10, weight: active ? .semibold : .regular))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(active ? brandViolet.opacity(0.16) : Color.primary.opacity(0.05)))
                .foregroundColor(active ? brandViolet : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func list(_ vis: [ClipItem]) -> some View {
        let firstUnpinned = vis.firstIndex { !$0.pinned }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(vis.enumerated()), id: \.element.id) { idx, item in
                        if idx == 0, item.pinned {
                            sectionHeader("Pinned")
                        }
                        if let fu = firstUnpinned, idx == fu, fu > 0 {
                            sectionHeader("Recent")
                        }
                        ClipRow(store: store, item: item, index: idx,
                                isSelected: store.selectedID == item.id,
                                isMulti: store.multiSelection.contains(item.id),
                                actions: actions)
                            .id(item.id)
                    }
                }
                .padding(6)
            }
            // Scroll ONLY on keyboard navigation (scrollTick): anchoring to
            // selectedID would make the list jump under the cursor on every hover.
            .onChange(of: store.scrollTick) { _, _ in
                if let id = store.selectedID { proxy.scrollTo(id) }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: store.search.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(brandGradient)
            if store.search.isEmpty {
                Text("Nothing here yet").font(.headline)
                Text("Copy something with ⌘C and it will show up here.\nSummon Pastello anywhere with ⇧⌘V.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No results").font(.headline)
                Text("Nothing contains “\(store.search)”.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var multiBar: some View {
        HStack(spacing: 8) {
            Text("\(store.multiSelection.count) items selected")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Paste together") { actions.pasteCombined() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(brandViolet)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(brandViolet.opacity(0.08))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("↩ paste · ⌘1-9 quick · ⌘click multi")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Spacer()
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
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
        }
        .padding(.horizontal, 10)
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
                .foregroundStyle(brandGradient)
            if let next = store.pasteQueue.first {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next: \(next.preview)")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text("\(store.pasteQueue.count) queued · ⌥⌘V pastes")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
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
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.1), lineWidth: 1))
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
            Text("Space or Esc to close · arrows to browse")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.vertical, 6)
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    private func header(_ item: ClipItem) -> some View {
        HStack(spacing: 8) {
            if let label = item.label {
                Image(systemName: "tag.fill").font(.system(size: 10)).foregroundColor(brandPink)
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
        HStack(alignment: .top, spacing: 8) {
            badge(flavor: flavor, swatch: swatch)
            VStack(alignment: .leading, spacing: 3) {
                if let label = item.label {
                    HStack(spacing: 4) {
                        Image(systemName: "tag.fill")
                            .font(.system(size: 8))
                            .foregroundColor(brandPink)
                        Text(label)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                }
                content
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            trailing
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(rowBackground))
        .overlay {
            if isMulti {
                RoundedRectangle(cornerRadius: 8).stroke(brandPink, lineWidth: 1.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
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

    private var rowBackground: Color {
        if isSelected { return Color.primary.opacity(0.09) }
        if hovering { return Color.primary.opacity(0.05) }
        return .clear
    }

    private var subtitle: String {
        var parts: [String] = []
        if let a = item.appName, !a.isEmpty { parts.append(a) }
        parts.append(Self.rel.localizedString(for: item.date, relativeTo: Date()))
        if let info = item.charInfo { parts.append(info) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var content: some View {
        if item.kind == .image, let img = store.thumbnail(for: item) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 72, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 6))
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
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(badgeColor(flavor).opacity(0.14))
                .frame(width: 26, height: 26)
            if let c = swatch {
                Circle()
                    .fill(Color(nsColor: c))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
            } else {
                Image(systemName: symbolName(flavor))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(badgeColor(flavor))
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        if hovering {
            HStack(spacing: 4) {
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
        } else if item.pinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 9))
                .foregroundColor(.orange)
        } else if index < 9 {
            Text("⌘\(index + 1)")
                .font(.system(size: 9).monospacedDigit())
                .foregroundColor(.secondary.opacity(0.6))
        }
    }
}
