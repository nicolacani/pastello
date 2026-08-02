import AppKit

enum ClipKind: String, Codable {
    case text, image, file
}

enum TextFlavor {
    case plain, url, email, color, code
}

struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipKind
    var text: String?
    var imageFile: String?
    var imageHash: String?
    var imageWidth: Int?
    var imageHeight: Int?
    var date: Date
    var pinned: Bool
    var appName: String?
    var appBundleID: String?
    // User-given name ("Project X API key"): last field with a default so the
    // existing memberwise init and decoding of old history stay unchanged.
    var label: String? = nil

    func matchesContent(of other: ClipItem) -> Bool {
        guard kind == other.kind else { return false }
        switch kind {
        case .text, .file:
            return text == other.text
        case .image:
            return imageHash != nil && imageHash == other.imageHash
        }
    }

    // preview/flavor/hexColor are re-evaluated on every row render:
    // they must stay O(1) in the text length (up to 100k chars),
    // so they work on a bounded prefix, never the whole string.

    var preview: String {
        switch kind {
        case .text:
            return String((text ?? "").prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines)
        case .file:
            let paths = (text ?? "").split(separator: "\n").map(String.init)
            let names = paths.map { ($0 as NSString).lastPathComponent }
            return names.joined(separator: ", ")
        case .image:
            if let w = imageWidth, let h = imageHeight { return "Image \(w)×\(h)" }
            return "Image"
        }
    }

    var flavor: TextFlavor {
        guard kind == .text, let raw = text else { return .plain }
        let t = String(raw.prefix(2000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .plain }
        if hexColor != nil { return .color }
        if !t.contains(where: { $0.isWhitespace }) {
            let low = t.lowercased()
            if low.hasPrefix("http://") || low.hasPrefix("https://") || low.hasPrefix("www.") { return .url }
            if t.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil { return .email }
        }
        if t.contains("\n"), t.contains("{") || t.contains("</") || t.contains(";") || t.contains("func ") || t.contains("def ") {
            return .code
        }
        return .plain
    }

    var hexColor: NSColor? {
        // utf8.count is O(1): rejects long texts right away without scanning them.
        guard kind == .text, let raw = text, raw.utf8.count <= 64 else { return nil }
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("#") else { return nil }
        t.removeFirst()
        guard t.count == 3 || t.count == 6, t.allSatisfy({ $0.isHexDigit }) else { return nil }
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: t).scanHexInt64(&v)
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255.0,
                       green: CGFloat((v >> 8) & 0xFF) / 255.0,
                       blue: CGFloat(v & 0xFF) / 255.0,
                       alpha: 1)
    }

    var charInfo: String? {
        switch kind {
        case .text:
            guard let t = text, t.utf8.count > 80 else { return nil }
            return "\(t.count) characters"
        case .file:
            let n = (text ?? "").split(separator: "\n").count
            return n > 1 ? "\(n) files" : nil
        case .image:
            return nil
        }
    }
}
