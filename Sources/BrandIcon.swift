import AppKit

/// The Pastello mark: the board with its clip and the card peeking out
/// behind, in outline, like the app icon. Same family as Myna (the bird)
/// and Earshot (the ear): pure path, transparent inside, round joins.
/// The same geometry lives in tools/makeicon.swift (app icon): if you change
/// the drawing there, update it here too.
enum BrandIcon {

    /// Glyph for NSStatusItem: rendered @2x, 18×18 logical pt.
    /// `color == nil` → template image (adapts to a light or dark menu bar).
    private static var cache: [String: NSImage] = [:]

    static func statusImage(color: NSColor? = nil) -> NSImage {
        // The appearance is part of the key: an image rendered in light mode
        // would stay wrong after the switch to dark.
        let appearance = NSApp.effectiveAppearance.name.rawValue
        let key = "\(color.map { $0.description } ?? "template")-\(appearance)"
        if let cached = cache[key] { return cached }
        let image = renderMark(pixels: 36, color: color ?? .black, widthRatio: 0.065)
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = (color == nil)
        cache[key] = image
        return image
    }

    // MARK: - Drawing

    /// The mark on a transparent background. Occluding the card behind means
    /// carving out the alpha, so it needs a canvas of its own: it cannot be
    /// drawn straight into a context that has already been painted.
    static func renderMark(pixels: Int, color: NSColor, widthRatio: CGFloat) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: pixels, height: pixels)

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        ctx.cgContext.setShouldAntialias(true)

        let side = CGFloat(pixels)
        let lineWidth = side * widthRatio
        let inset = 0.5 + lineWidth / 2
        let box = NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: inset, dy: inset)
        draw(in: box, lineWidth: lineWidth, color: color)

        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.addRepresentation(rep)
        return image
    }

    /// Unit geometry [0,1]x[0,1], y pointing up: the board as the dominant
    /// shape and the clip as the only detail, a separate form resting on the
    /// top edge. Two rules learned the hard way, over many attempts: a clip
    /// merged into the outline gives a jar-like profile, and a third figure
    /// (the card behind) at 18 pt reads as an orphan stroke.
    /// Same grammar as the bird and the ear: one shape, one detail.
    private static func draw(in box: NSRect, lineWidth: CGFloat, color: NSColor) {
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

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

        func stroke(_ path: NSBezierPath) {
            let m = map(path)
            color.setStroke()
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
        stroke(clip)
    }
}
