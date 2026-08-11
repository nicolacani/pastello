// Generates the Pastello icon and the menu bar previews.
// Same language as Inkdown, Myna and Earshot: Big Sur rounded rect, warm cream
// background, outline mark with a transparent inside in the app's own dark
// tint, one ORANGE accent — the shared signature — on a detail that means
// something (here the CLIP, the part that grabs), and a thin dark edge that
// keeps the icon off light backgrounds (without it, at 16 px on the Finder's
// white the tile disappears).
// The mark geometry is the same as Sources/BrandIcon.swift (if you change the
// drawing there, update it here too).
// Usage: swift tools/makeicon.swift assets
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets"
let iconsetPath = outDir + "/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

// MARK: - Family palette (anchored to the Inkdown icon)

let creamTop    = NSColor(srgbRed: 0xF7/255.0, green: 0xF5/255.0, blue: 0xEE/255.0, alpha: 1)
let creamBottom = NSColor(srgbRed: 0xED/255.0, green: 0xE9/255.0, blue: 0xDE/255.0, alpha: 1)
/// Pastello's own dark tint: a very dark grey-olive (Myna pulls to cold grey,
/// Earshot to warm espresso). It tells the apps apart without breaking the set.
let markColor   = NSColor(srgbRed: 0x2A/255.0, green: 0x2A/255.0, blue: 0x24/255.0, alpha: 1)
/// The accent shared by the whole family.
let accentColor = NSColor(srgbRed: 0xC0/255.0, green: 0x56/255.0, blue: 0x2A/255.0, alpha: 1)

func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    return rep
}

func inContext(_ rep: NSBitmapImageRep, _ draw: (NSGraphicsContext) -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.setShouldAntialias(true)
    draw(ctx)
    ctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Mark (twin of Sources/BrandIcon.swift)

/// `accent == nil` → the clip takes the same color as the board (menu bar
/// glyph, which must stay one single template colour).
func drawMark(in box: NSRect, lineWidth: CGFloat, color: NSColor, accent: NSColor? = nil) {
    // The drawing is 0.76 tall in unit coordinates: it grows around the
    // center so it fills the square the way the other two marks do,
    // without touching the stroke weight (which stays the family's).
    let grow: CGFloat = 1.0
    func map(_ path: NSBezierPath) -> NSBezierPath {
        let copy = path.copy() as! NSBezierPath
        var t = AffineTransform()
        t.translate(x: box.midX, y: box.midY)
        t.scale(x: box.width * grow, y: box.height * grow)
        t.translate(x: -0.5, y: -0.5)
        copy.transform(using: t)
        return copy
    }

    func stroke(_ path: NSBezierPath, _ ink: NSColor? = nil) {
        let m = map(path)
        (ink ?? color).setStroke()
        m.lineWidth = lineWidth
        m.lineCapStyle = .round
        m.lineJoinStyle = .round
        m.stroke()
    }

    /// Rectangle with filleted corners, built from vertices and tangent
    /// arcs. Separate radii at the top and at the bottom: tight top
    /// corners keep the upper edge flat, and that is what tells a board
    /// apart from a bottle with a cap.
    func rrect(_ l: CGFloat, _ b: CGFloat, _ r: CGFloat, _ t: CGFloat,
               _ rBottom: CGFloat, _ rTop: CGFloat? = nil) -> NSBezierPath {
        let pts = [P(l, b), P(r, b), P(r, t), P(l, t)]
        let radii = [rBottom, rBottom, rTop ?? rBottom, rTop ?? rBottom]
        let path = NSBezierPath()
        path.move(to: CGPoint(x: (pts[3].x + pts[0].x) / 2, y: (pts[3].y + pts[0].y) / 2))
        for i in 0..<4 {
            path.appendArc(from: pts[i], to: pts[(i + 1) % 4], radius: radii[i])
        }
        path.close()
        return path
    }

    // Board: the dominant shape.
    stroke(rrect(0.190, 0.030, 0.810, 0.840, 0.125, 0.085))

    // Clip: its area (plus a margin) is carved out, so the board outline
    // breaks off cleanly where the clip passes instead of crossing it or
    // touching it: under that light, at 18 pt, the head becomes a blob.
    let clip = rrect(0.350, 0.750, 0.650, 0.970, 0.055)
    let mapped = map(clip)
    let ctx = NSGraphicsContext.current!
    ctx.compositingOperation = .destinationOut
    NSColor.black.setFill()
    NSColor.black.setStroke()
    mapped.fill()
    mapped.lineWidth = lineWidth * 2.2
    mapped.lineJoinStyle = .round
    mapped.stroke()
    ctx.compositingOperation = .sourceOver
    // The clip is the one thing that grabs, so it carries the family's orange.
    stroke(clip, accent)
}

/// The mark on a transparent canvas: the occlusion carves out the alpha, so
/// it cannot be drawn straight over a background that is already painted.
/// `minLineWidth` is the family floor (one pixel of the finished tile) brought
/// back into this canvas' scale: without it, at 16 px the stroke would come out
/// under half a pixel and the dark mark would fade into the cream.
func markImage(px: Int, color: NSColor, accent: NSColor? = nil,
               widthRatio: CGFloat, minLineWidth: CGFloat = 0) -> NSImage {
    let rep = bitmap(px, px)
    inContext(rep) { _ in
        let side = CGFloat(px)
        let lineWidth = max(side * widthRatio, minLineWidth)
        let inset = 0.5 + lineWidth / 2
        drawMark(in: NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: inset, dy: inset),
                 lineWidth: lineWidth, color: color, accent: accent)
    }
    let image = NSImage(size: NSSize(width: px, height: px))
    image.addRepresentation(rep)
    return image
}

// MARK: - App icon

func renderIcon(px: Int) -> Data {
    let rep = bitmap(px, px)
    inContext(rep) { _ in
        let c = CGFloat(px)
        let rect = NSRect(x: 0, y: 0, width: c, height: c).insetBy(dx: c * 0.098, dy: c * 0.098)
        let radius = rect.width * 0.225
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        // Warm cream, a touch lighter at the top.
        NSGradient(colors: [creamBottom, creamTop], atLocations: [0.0, 1.0], colorSpace: .sRGB)!
            .draw(in: shape, angle: 90)

        NSGraphicsContext.saveGraphicsState()
        shape.addClip()

        // The mark is 0.94 tall inside its own square and has to cover 74% of
        // the tile, like the bird in Myna and the ear in Earshot. It is drawn
        // on a transparent canvas of its own and only then composited, because
        // the clip carves the board's alpha: over an already painted background
        // that occlusion would punch a hole in the cream too.
        let markBox = rect.insetBy(dx: rect.width * 0.1065, dy: rect.width * 0.1065)
        let side = max(Int(markBox.width.rounded()), 16)
        // The family stroke is max(tile * 0.026, 1) — in this canvas' scale.
        let toTile = markBox.width / CGFloat(side)
        markImage(px: side, color: markColor, accent: accentColor,
                  widthRatio: 0.0411, minLineWidth: 1.0 / toTile).draw(in: markBox)

        NSGraphicsContext.restoreGraphicsState()

        // Edge: drawn LAST and outside the clip, otherwise the shape would cut
        // it in half. It is what keeps the icon off light backgrounds at the
        // small sizes.
        NSColor(white: 0, alpha: 0.22).setStroke()
        let edge = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        edge.lineWidth = max(c * 0.014, 1.0)
        edge.stroke()
    }
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Menu bar previews

func strip(dark: Bool) -> Data {
    let rep = bitmap(600, 88)
    inContext(rep) { _ in
        (dark ? NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
              : NSColor(srgbRed: 0.95, green: 0.95, blue: 0.96, alpha: 1)).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 600, height: 88)).fill()
        markImage(px: 36, color: dark ? .white : .black, widthRatio: 0.065)
            .draw(in: NSRect(x: 40, y: 26, width: 36, height: 36))
    }
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Output

let specs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in specs {
    try renderIcon(px: px).write(to: URL(fileURLWithPath: iconsetPath + "/" + name))
}
try renderIcon(px: 512).write(to: URL(fileURLWithPath: outDir + "/logo-preview.png"))
try strip(dark: false).write(to: URL(fileURLWithPath: outDir + "/menubar-light.png"))
try strip(dark: true).write(to: URL(fileURLWithPath: outDir + "/menubar-dark.png"))
print("Icon and previews written to \(outDir)")
