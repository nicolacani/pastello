// Generates 3 variants of the Pastello icon + template glyph for the menu bar,
// with previews at real sizes for aesthetic judging.
// Usage: swift tools/makevariants.swift assets/variants
import AppKit

let outBase = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/variants"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha)
}

struct Variant {
    let name: String
    let bgColors: [NSColor]
    let bgAngle: CGFloat
    let backCard: NSColor
    let midCard: NSColor
    let glow: CGFloat // intensity of the glow at top left
}

let variants: [Variant] = [
    Variant(name: "v1", bgColors: [color(0x6D5DF6), color(0xA455F0), color(0xF25C9C)],
            bgAngle: -55, backCard: color(0x7BE3BE), midCard: color(0xFFD97A), glow: 0.14),
    Variant(name: "v2", bgColors: [color(0xFB923C), color(0xEC4899)],
            bgAngle: -60, backCard: color(0x7DD3FC), midCard: color(0xFDE047), glow: 0.16),
    Variant(name: "v3", bgColors: [color(0x3B2FA3), color(0x7C3AED)],
            bgAngle: -65, backCard: color(0xF9A8D4), midCard: color(0xFDE68A), glow: 0.20),
]

func path(cx: CGFloat, cy: CGFloat, x: CGFloat = 0, y: CGFloat = 0,
          w: CGFloat, h: CGFloat, r: CGFloat, rot: CGFloat, s: CGFloat) -> NSBezierPath {
    let rect = NSRect(x: (x - w / 2) * s, y: (y - h / 2) * s, width: w * s, height: h * s)
    let p = NSBezierPath(roundedRect: rect, xRadius: r * s, yRadius: r * s)
    p.transform(using: AffineTransform(rotationByDegrees: rot))
    p.transform(using: AffineTransform(translationByX: cx * s, byY: cy * s))
    return p
}

func circle(cx: CGFloat, cy: CGFloat, x: CGFloat, y: CGFloat, radius: CGFloat,
            rot: CGFloat, s: CGFloat) -> NSBezierPath {
    let rect = NSRect(x: (x - radius) * s, y: (y - radius) * s,
                      width: radius * 2 * s, height: radius * 2 * s)
    let p = NSBezierPath(ovalIn: rect)
    p.transform(using: AffineTransform(rotationByDegrees: rot))
    p.transform(using: AffineTransform(translationByX: cx * s, byY: cy * s))
    return p
}

func withShadow(blur: CGFloat, dy: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow()
    sh.shadowBlurRadius = blur
    sh.shadowOffset = NSSize(width: 0, height: -dy)
    sh.shadowColor = NSColor.black.withAlphaComponent(alpha)
    sh.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func bitmap(_ wpx: Int, _ hpx: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: wpx, pixelsHigh: hpx,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: wpx, height: hpx)
    return rep
}

func inContext(_ rep: NSBitmapImageRep, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }

// MARK: - App icon (1024 grid)

// Card with a subtle vertical gradient to add depth.
func fillCard(_ p: NSBezierPath, base: NSColor) {
    let darker = base.blended(withFraction: 0.10, of: .black) ?? base
    NSGradient(colors: [base, darker])!.draw(in: p, angle: -90)
}

func renderIcon(_ v: Variant, px: Int) -> Data {
    let s = CGFloat(px) / 1024.0
    let rep = bitmap(px, px)
    inContext(rep) {
        // Squircle background with gradient + soft glow at top left
        let bgRect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185 * s, yRadius: 185 * s)
        NSGradient(colors: v.bgColors)!.draw(in: bg, angle: v.bgAngle)
        NSGradient(colors: [NSColor.white.withAlphaComponent(v.glow),
                            NSColor.white.withAlphaComponent(0)])!
            .draw(in: bg, relativeCenterPosition: NSPoint(x: -0.45, y: 0.55))

        // Three fanned-out cards
        withShadow(blur: 26 * s, dy: 16 * s, alpha: 0.22) {
            fillCard(path(cx: 420, cy: 555, w: 450, h: 330, r: 42, rot: 13, s: s), base: v.backCard)
        }
        withShadow(blur: 26 * s, dy: 16 * s, alpha: 0.22) {
            fillCard(path(cx: 500, cy: 515, w: 470, h: 345, r: 42, rot: 4, s: s), base: v.midCard)
        }
        let fcx: CGFloat = 560, fcy: CGFloat = 455, frot: CGFloat = -7
        withShadow(blur: 40 * s, dy: 22 * s, alpha: 0.30) {
            fillCard(path(cx: fcx, cy: fcy, w: 490, h: 360, r: 44, rot: frot, s: s), base: .white)
        }

        // White card content: pink dot + text lines
        color(0xF2599C).setFill()
        circle(cx: fcx, cy: fcy, x: -165, y: 70, radius: 21, rot: frot, s: s).fill()
        color(0xC6CDDA).setFill()
        path(cx: fcx, cy: fcy, x: 35, y: 70, w: 230, h: 30, r: 15, rot: frot, s: s).fill()
        path(cx: fcx, cy: fcy, x: -15, y: 5, w: 330, h: 30, r: 15, rot: frot, s: s).fill()
        path(cx: fcx, cy: fcy, x: -60, y: -60, w: 240, h: 30, r: 15, rot: frot, s: s).fill()

        // Metal clip straddling the top edge, with a hole
        withShadow(blur: 12 * s, dy: 7 * s, alpha: 0.25) {
            let clip = path(cx: fcx, cy: fcy, x: 0, y: 178, w: 170, h: 95, r: 32, rot: frot, s: s)
            NSGradient(colors: [color(0xD5DCE6), color(0x9AA6B6)])!.draw(in: clip, angle: -90)
        }
        NSColor.white.setFill()
        circle(cx: fcx, cy: fcy, x: 0, y: 170, radius: 24, rot: frot, s: s).fill()
    }
    return png(rep)
}

// MARK: - Menu bar glyph (18pt grid, template: alpha only)

func glyphInto(_ s: CGFloat, _ ink: NSColor) {
    let ctx = NSGraphicsContext.current!
    // back card, offset well to the top left so the stack reads clearly
    let back = path(cx: 7.2, cy: 10.4, w: 10.4, h: 7.6, r: 2.0, rot: 14, s: s)
    ink.setFill()
    back.fill()
    // front card: first a separating halo is "cut out", then it's filled
    let front = path(cx: 10.2, cy: 7.4, w: 11.2, h: 8.4, r: 2.1, rot: -7, s: s)
    ctx.compositingOperation = .destinationOut
    front.fill()
    front.lineWidth = 2.0 * s
    front.stroke()
    ctx.compositingOperation = .sourceOver
    ink.setFill()
    front.fill()
    // clip: separating halo + body + hole
    let clip = path(cx: 10.2, cy: 7.4, x: 0, y: 4.0, w: 5.4, h: 3.0, r: 1.2, rot: -7, s: s)
    ctx.compositingOperation = .destinationOut
    clip.lineWidth = 1.6 * s
    clip.stroke()
    ctx.compositingOperation = .sourceOver
    ink.setFill()
    clip.fill()
    ctx.compositingOperation = .destinationOut
    circle(cx: 10.2, cy: 7.4, x: 0, y: 3.95, radius: 0.9, rot: -7, s: s).fill()
    ctx.compositingOperation = .sourceOver
}

func renderGlyph(px: Int, ink: NSColor) -> Data {
    let rep = bitmap(px, px)
    inContext(rep) { glyphInto(CGFloat(px) / 18.0, ink) }
    return png(rep)
}

// Menu bar-style strip (at 2x) to judge the glyph in its real context.
func renderStrip(dark: Bool) -> Data {
    let rep = bitmap(600, 88)
    inContext(rep) {
        (dark ? color(0x1D1D1F) : color(0xF2F2F7)).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 600, height: 88)).fill()
        NSGraphicsContext.current!.saveGraphicsState()
        let t = NSAffineTransform()
        t.translateX(by: 40, yBy: 26)
        t.concat()
        glyphInto(2.0, dark ? .white : .black)
        NSGraphicsContext.current!.restoreGraphicsState()
    }
    return png(rep)
}

// MARK: - Output

for v in variants {
    let dir = outBase + "/" + v.name
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for px in [512, 128, 64, 32] {
        try renderIcon(v, px: px).write(to: URL(fileURLWithPath: "\(dir)/app-\(px).png"))
    }
}
// The glyph is identical for all variants: saved just once.
try FileManager.default.createDirectory(atPath: outBase, withIntermediateDirectories: true)
try renderGlyph(px: 36, ink: .black).write(to: URL(fileURLWithPath: outBase + "/glyph-36.png"))
try renderStrip(dark: false).write(to: URL(fileURLWithPath: outBase + "/menubar-light.png"))
try renderStrip(dark: true).write(to: URL(fileURLWithPath: outBase + "/menubar-dark.png"))
print("Variants written to \(outBase)")
