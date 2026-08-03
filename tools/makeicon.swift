// Generates the Pastello app icon (the "refined v3" design picked by the judging panel):
// a fan of pastel cards around a shared pivot on an indigo→violet background,
// dark metal clip, size-adaptive detail. Also generates the outline-style
// template glyph for the menu bar, consistent with the icon.
// Usage: swift tools/makeicon.swift assets
import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets"
let iconsetPath = outDir + "/AppIcon.iconset"
let menubarPath = outDir + "/menubar"
try FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)
try FileManager.default.createDirectory(atPath: menubarPath, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha)
}

func deg(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

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

// MARK: - App icon (1024 grid, fan around a shared pivot)

struct Card {
    let rot: CGFloat
    let w: CGFloat
    let h: CGFloat
    let center: NSPoint
}

// Pivot at bottom center: the cards rotate like a fan of cards in hand.
func makeCards() -> (back: Card, mid: Card, front: Card) {
    let pivot = NSPoint(x: 512, y: 285)
    let dist: CGFloat = 215
    func card(rot: CGFloat, w: CGFloat, h: CGFloat) -> Card {
        let cx = pivot.x - dist * sin(deg(rot))
        let cy = pivot.y + dist * cos(deg(rot))
        return Card(rot: rot, w: w, h: h, center: NSPoint(x: cx, y: cy))
    }
    return (card(rot: 16, w: 484, h: 352), card(rot: 7, w: 492, h: 360), card(rot: -3, w: 500, h: 368))
}

// Card with a vertical gradient and a sliver of light along the top edge.
func fillCard(_ c: Card, base: NSColor, s: CGFloat, hairline: Bool) {
    let p = path(cx: c.center.x, cy: c.center.y, w: c.w, h: c.h, r: 44, rot: c.rot, s: s)
    let darker = base.blended(withFraction: 0.10, of: .black) ?? base
    NSGradient(colors: [base, darker])!.draw(in: p, angle: -90)
    // inner light on the edge (clipped to the card)
    NSGraphicsContext.saveGraphicsState()
    p.addClip()
    NSColor.white.withAlphaComponent(0.22).setStroke()
    p.lineWidth = 5 * s
    p.stroke()
    NSGraphicsContext.restoreGraphicsState()
    if hairline {
        NSColor.black.withAlphaComponent(0.08).setStroke()
        p.lineWidth = max(1, 2 * s)
        p.stroke()
    }
}

func renderIcon(px: Int) -> Data {
    let s = CGFloat(px) / 1024.0
    let rep = bitmap(px, px)
    inContext(rep) {
        // Background: coral squircle, the brand accent. A light tonal shade
        // (same hue, just brighter at the top): depth without rainbows.
        let bgRect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let bg = NSBezierPath(roundedRect: bgRect, xRadius: 185 * s, yRadius: 185 * s)
        NSGradient(colors: [color(0xF07A4A), color(0xE55A28)])!
            .draw(in: bg, angle: -90)
        // glow behind the card group to lift it off the background
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.08),
                            NSColor.white.withAlphaComponent(0)])!
            .draw(in: bg, relativeCenterPosition: NSPoint(x: -0.05, y: 0.10))

        let cards = makeCards()
        // Detail level per size: below 64px the details turn to mush.
        let full = px >= 128
        let medium = px >= 64
        let simple = px >= 32
        let shadowMul: CGFloat = full ? 1.0 : (medium ? 0.5 : 0)
        let hairline = shadowMul == 0

        func drop(_ blur: CGFloat, _ dy: CGFloat, _ a: CGFloat, _ f: () -> Void) {
            if shadowMul > 0 {
                withShadow(blur: blur * s, dy: dy * s, alpha: a * shadowMul, f)
            } else {
                f()
            }
        }

        drop(18, 8, 0.20) { fillCard(cards.back, base: color(0x8FE0BE), s: s, hairline: hairline) }
        drop(18, 8, 0.20) { fillCard(cards.mid, base: color(0xFFD34D), s: s, hairline: hairline) }
        drop(32, 16, 0.28) { fillCard(cards.front, base: .white, s: s, hairline: hairline) }

        let f = cards.front
        // White card content: coral dot + text lines (adaptive)
        if medium {
            color(0xE5551F).setFill()
            let dotR: CGFloat = full ? 22 : 26
            circle(cx: f.center.x, cy: f.center.y, x: -165, y: 70, radius: dotR, rot: f.rot, s: s).fill()
        }
        color(0xC6CDDA).setFill()
        if full {
            path(cx: f.center.x, cy: f.center.y, x: 35, y: 70, w: 230, h: 30, r: 15, rot: f.rot, s: s).fill()
            path(cx: f.center.x, cy: f.center.y, x: -15, y: 5, w: 330, h: 30, r: 15, rot: f.rot, s: s).fill()
            path(cx: f.center.x, cy: f.center.y, x: -60, y: -60, w: 240, h: 30, r: 15, rot: f.rot, s: s).fill()
        } else if simple {
            path(cx: f.center.x, cy: f.center.y, x: 30, y: 60, w: 240, h: 42, r: 21, rot: f.rot, s: s).fill()
            path(cx: f.center.x, cy: f.center.y, x: -30, y: -35, w: 300, h: 42, r: 21, rot: f.rot, s: s).fill()
        }

        // Dark metal clip straddling the top edge, with a punched hole
        drop(12, 7, 0.28) {
            let clip = path(cx: f.center.x, cy: f.center.y, x: 0, y: 190, w: 200, h: 100, r: 34, rot: f.rot, s: s)
            NSGradient(colors: [color(0x8B98AA), color(0x5A6879)])!.draw(in: clip, angle: -90)
        }
        if medium {
            // specular highlight on the clip's top edge
            color(0xE8EDF4, 0.55).setFill()
            path(cx: f.center.x, cy: f.center.y, x: 0, y: 224, w: 150, h: 9, r: 4.5, rot: f.rot, s: s).fill()
        }
        // hole: dark rim + white interior
        color(0x414C5B).setFill()
        circle(cx: f.center.x, cy: f.center.y, x: 0, y: 162, radius: 25, rot: f.rot, s: s).fill()
        NSColor.white.setFill()
        circle(cx: f.center.x, cy: f.center.y, x: 0, y: 160, radius: 19, rot: f.rot, s: s).fill()
    }
    return png(rep)
}

// MARK: - Menu bar glyph (18pt grid, SF Symbols-style outline)

func glyphInto(_ s: CGFloat, _ ink: NSColor) {
    let ctx = NSGraphicsContext.current!
    let stroke: CGFloat = 1.25 * s
    ink.setStroke()
    ink.setFill()

    let frontCX: CGFloat = 9.6, frontCY: CGFloat = 7.7, frontRot: CGFloat = -6

    // Edge of the back card peeking out at top left
    let back = path(cx: 7.6, cy: 9.7, w: 11.0, h: 8.2, r: 1.9, rot: 8, s: s)
    back.lineWidth = stroke
    back.stroke()

    // The front card's area (with margin) erases whatever passes underneath
    let front = path(cx: frontCX, cy: frontCY, w: 11.6, h: 8.6, r: 2.0, rot: frontRot, s: s)
    ctx.compositingOperation = .destinationOut
    front.fill()
    front.lineWidth = 3.2 * s
    front.stroke()
    ctx.compositingOperation = .sourceOver

    // Front card as an outline
    front.lineWidth = stroke
    front.stroke()

    // Clip tab straddling the top edge: first a gap is opened in the card's
    // stroke, then the tab and its little dot are drawn.
    let tab = path(cx: frontCX, cy: frontCY, x: 0, y: 4.3, w: 4.8, h: 2.7, r: 1.1, rot: frontRot, s: s)
    ctx.compositingOperation = .destinationOut
    tab.fill()
    tab.lineWidth = 2.2 * s
    tab.stroke()
    ctx.compositingOperation = .sourceOver
    tab.lineWidth = stroke
    tab.stroke()
    circle(cx: frontCX, cy: frontCY, x: 0, y: 4.3, radius: 0.8, rot: frontRot, s: s).fill()
}

func renderGlyph(px: Int, ink: NSColor) -> Data {
    let rep = bitmap(px, px)
    inContext(rep) { glyphInto(CGFloat(px) / 18.0, ink) }
    return png(rep)
}

func renderStrip(dark: Bool) -> Data {
    // The glyph must be rendered in its own bitmap: it uses destinationOut,
    // which in a shared bitmap would punch through the strip's background too.
    let glyphImg = NSImage(data: renderGlyph(px: 36, ink: dark ? .white : .black))!
    let rep = bitmap(600, 88)
    inContext(rep) {
        (dark ? color(0x1D1D1F) : color(0xF2F2F7)).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 600, height: 88)).fill()
        glyphImg.draw(in: NSRect(x: 40, y: 26, width: 36, height: 36))
    }
    return png(rep)
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
try renderGlyph(px: 18, ink: .black).write(to: URL(fileURLWithPath: menubarPath + "/MenuBarIcon.png"))
try renderGlyph(px: 36, ink: .black).write(to: URL(fileURLWithPath: menubarPath + "/MenuBarIcon@2x.png"))
try renderStrip(dark: false).write(to: URL(fileURLWithPath: outDir + "/menubar-light.png"))
try renderStrip(dark: true).write(to: URL(fileURLWithPath: outDir + "/menubar-dark.png"))
print("Icon, glyph and previews written to \(outDir)")
