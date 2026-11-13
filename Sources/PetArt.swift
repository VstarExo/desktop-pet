import AppKit

// The pet's looks. Everything is drawn with shapes in a 160 x 180 design canvas,
// y pointing up, with the pet standing at `origin` and facing right.

private func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

struct Coat {
    let name: String
    let body: CGColor
    let shade: CGColor      // forehead stripes and tail tip
    let belly: CGColor      // belly, muzzle and paws
    let outline: CGColor
    let innerEar: CGColor
    let nose: CGColor
    let eye: CGColor
    let faceLine: CGColor   // closed eyes and whiskers
    let lightEyes: Bool     // bright iris with a slit pupil, for dark fur

    static let all: [Coat] = [
        Coat(name: "Marmalade", body: rgb(0xF6A957), shade: rgb(0xDC8232), belly: rgb(0xFFF3E0),
             outline: rgb(0x5B3A24), innerEar: rgb(0xFFB9A6), nose: rgb(0xEE7C87),
             eye: rgb(0x2E1F16), faceLine: rgb(0x5B3A24), lightEyes: false),
        Coat(name: "Smoke", body: rgb(0xAEB6C1), shade: rgb(0x808A98), belly: rgb(0xF5F7FA),
             outline: rgb(0x3C424B), innerEar: rgb(0xF7B8C0), nose: rgb(0xE98A97),
             eye: rgb(0x23272D), faceLine: rgb(0x3C424B), lightEyes: false),
        Coat(name: "Tuxedo", body: rgb(0x3A3A46), shade: rgb(0x2C2C36), belly: rgb(0xFFFFFF),
             outline: rgb(0x1B1B22), innerEar: rgb(0xE79AA6), nose: rgb(0xF08C9A),
             eye: rgb(0xC9E265), faceLine: rgb(0xF1EEE6), lightEyes: true),
        Coat(name: "Snow", body: rgb(0xFBF7F0), shade: rgb(0xE6DCCB), belly: rgb(0xFFFFFF),
             outline: rgb(0x6E5D50), innerEar: rgb(0xFFC2C9), nose: rgb(0xF0919C),
             eye: rgb(0x3A2C24), faceLine: rgb(0x6E5D50), lightEyes: false),
    ]
}

enum PetArt {
    static let canvas = CGSize(width: 160, height: 180)
    static let origin = CGPoint(x: 80, y: 24)   // between the feet
    static let grab = CGPoint(x: 0, y: 70)      // the scruff, relative to origin
    static let headY: CGFloat = 50

    private static let pupil = rgb(0x2B1D14)

    // MARK: Pet

    static func draw(_ ctx: CGContext, pose p: Pose, facing: CGFloat, coat c: Coat) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.translateBy(x: origin.x, y: origin.y)

        if p.shadow > 0 {
            let spread = max(0.5, 1 - p.lift / 40)
            ellipse(ctx, 0, -1, 25 * spread * p.bodySX, 4.5 * spread, fill: rgb(0x000000, 0.16 * p.shadow))
        }

        ctx.translateBy(x: 0, y: p.lift)
        ctx.translateBy(x: grab.x, y: grab.y)
        ctx.rotate(by: p.rotation)
        ctx.translateBy(x: -grab.x, y: -grab.y)
        ctx.scaleBy(x: facing, y: 1)
        ctx.rotate(by: p.lean)
        ctx.scaleBy(x: p.sx, y: p.sy)

        if p.tail != .wrap { tail(ctx, p, c) }

        ellipse(ctx, 0, 18 * p.bodySY, 21 * p.bodySX, 18 * p.bodySY, fill: c.body, stroke: c.outline, lineWidth: 2.5)
        ellipse(ctx, 2, 13 * p.bodySY, 12 * p.bodySX, 10.5 * p.bodySY, fill: c.belly)

        if p.tail == .wrap {
            tail(ctx, p, c)
        } else {
            ellipse(ctx, -10 + p.footA.x, 2.5 + p.footA.y, 7.5, 4.5, fill: c.belly, stroke: c.outline, lineWidth: 2.2)
            ellipse(ctx, 10 + p.footB.x, 2.5 + p.footB.y, 7.5, 4.5, fill: c.belly, stroke: c.outline, lineWidth: 2.2)
        }

        head(ctx, p, c)
    }

    private static func tail(_ ctx: CGContext, _ p: Pose, _ c: Coat) {
        let s = p.tailSway
        let a, b, d, e: CGPoint
        switch p.tail {
        case .up:
            a = CGPoint(x: -15, y: 9)
            b = CGPoint(x: -36, y: 6)
            d = CGPoint(x: -42 + s * 5, y: 30)
            e = CGPoint(x: -31 + s * 9, y: 45)
        case .hang:
            a = CGPoint(x: -15, y: 9)
            b = CGPoint(x: -30, y: 8)
            d = CGPoint(x: -33 + s * 4, y: -4)
            e = CGPoint(x: -29 + s * 8, y: -14)
        case .wrap:
            a = CGPoint(x: -24, y: 8)
            b = CGPoint(x: -38, y: 7)
            d = CGPoint(x: -30, y: 1.5)
            e = CGPoint(x: -2, y: 3.5)
        }

        func stroke(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ color: CGColor, _ width: CGFloat) {
            ctx.move(to: p0)
            ctx.addCurve(to: p3, control1: p1, control2: p2)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(width)
            ctx.strokePath()
        }
        stroke(a, b, d, e, c.outline, 10.5)
        stroke(a, b, d, e, c.body, 6)

        // Tail tip: the last stretch of the same curve, in the shade color.
        func mix(_ u: CGPoint, _ v: CGPoint, _ t: CGFloat) -> CGPoint {
            CGPoint(x: u.x + (v.x - u.x) * t, y: u.y + (v.y - u.y) * t)
        }
        let t: CGFloat = 0.72
        let ab = mix(a, b, t), bd = mix(b, d, t), de = mix(d, e, t)
        let abd = mix(ab, bd, t), bde = mix(bd, de, t)
        stroke(mix(abd, bde, t), bde, de, e, c.shade, 6)
    }

    private static func head(_ ctx: CGContext, _ p: Pose, _ c: Coat) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.translateBy(x: p.headDX, y: headY + p.headDY)
        ctx.rotate(by: p.headTilt)

        for side: CGFloat in [-1, 1] {
            polygon(ctx, [CGPoint(x: 25 * side, y: 8), CGPoint(x: 22 * side, y: 33), CGPoint(x: 7 * side, y: 19)])
            ctx.setFillColor(c.body)
            ctx.setStrokeColor(c.outline)
            ctx.setLineWidth(2.5)
            ctx.drawPath(using: .fillStroke)
            polygon(ctx, [CGPoint(x: 21.5 * side, y: 14), CGPoint(x: 20.5 * side, y: 27.5), CGPoint(x: 12 * side, y: 18.5)])
            ctx.setFillColor(c.innerEar)
            ctx.fillPath()
        }

        let skull = CGRect(x: -27, y: -22, width: 54, height: 44)
        ctx.setFillColor(c.body)
        ctx.fillEllipse(in: skull)

        ctx.saveGState()
        ctx.addEllipse(in: skull)
        ctx.clip()
        ctx.setStrokeColor(c.shade)
        ctx.setLineWidth(3.2)
        for (x0, y0, x1, y1) in [(0.0, 22.0, 0.0, 13.0), (-7.5, 21.0, -6.5, 14.5), (7.5, 21.0, 6.5, 14.5)] {
            ctx.move(to: CGPoint(x: x0, y: y0))
            ctx.addLine(to: CGPoint(x: x1, y: y1))
            ctx.strokePath()
        }
        ellipse(ctx, 0, -9.5, 10, 6.5, fill: c.belly)
        ctx.restoreGState()

        ctx.setStrokeColor(c.outline)
        ctx.setLineWidth(2.5)
        ctx.strokeEllipse(in: skull)

        // Whiskers
        ctx.setStrokeColor(c.faceLine.copy(alpha: 0.55) ?? c.faceLine)
        ctx.setLineWidth(1.1)
        for side: CGFloat in [-1, 1] {
            ctx.move(to: CGPoint(x: 21 * side, y: -5))
            ctx.addLine(to: CGPoint(x: 33 * side, y: -3))
            ctx.move(to: CGPoint(x: 21 * side, y: -8.5))
            ctx.addLine(to: CGPoint(x: 33 * side, y: -10.5))
        }
        ctx.strokePath()

        // Blush
        for side: CGFloat in [-1, 1] {
            ellipse(ctx, 18 * side, -8, 4.5, 2.6, fill: rgb(0xFF7F9E, 0.4))
        }

        let gaze = CGPoint(x: p.look.x * 2.2, y: p.look.y * 1.6)
        for side: CGFloat in [-1, 1] {
            eye(ctx, at: CGPoint(x: 11 * side + gaze.x, y: -1 + gaze.y), p, c)
        }

        // Nose
        let nx = gaze.x * 0.4, ny = -6.3 + gaze.y * 0.4
        polygon(ctx, [CGPoint(x: nx - 2.2, y: ny + 1), CGPoint(x: nx + 2.2, y: ny + 1), CGPoint(x: nx, y: ny - 1.4)])
        ctx.setFillColor(c.nose)
        ctx.setStrokeColor(c.nose)
        ctx.setLineWidth(1)
        ctx.drawPath(using: .fillStroke)

        // Mouth
        let my = ny - 2.2
        switch p.mouth {
        case .open:
            ellipse(ctx, nx, my - 3, 2.3, 2.8, fill: pupil)
        case .smile, .grin:
            if p.mouth == .grin {
                ctx.move(to: CGPoint(x: nx - 2.6, y: my - 1.8))
                ctx.addQuadCurve(to: CGPoint(x: nx + 2.6, y: my - 1.8), control: CGPoint(x: nx, y: my - 7.5))
                ctx.closePath()
                ctx.setFillColor(rgb(0xE8607A))
                ctx.fillPath()
            }
            ctx.move(to: CGPoint(x: nx - 5, y: my - 0.6))
            ctx.addQuadCurve(to: CGPoint(x: nx, y: my), control: CGPoint(x: nx - 2.5, y: my - 4))
            ctx.addQuadCurve(to: CGPoint(x: nx + 5, y: my - 0.6), control: CGPoint(x: nx + 2.5, y: my - 4))
            ctx.setStrokeColor(c.outline)
            ctx.setLineWidth(1.5)
            ctx.strokePath()
        }
    }

    private static func eye(_ ctx: CGContext, at o: CGPoint, _ p: Pose, _ c: Coat) {
        ctx.setStrokeColor(c.faceLine)
        ctx.setLineWidth(2)
        switch p.eyes {
        case .open:
            if c.lightEyes {
                ellipse(ctx, o.x, o.y, 4.4, 5.6, fill: c.eye)
                ellipse(ctx, o.x + p.look.x * 0.8, o.y + p.look.y * 0.5, 1.9, 4.3, fill: pupil)
            } else {
                ellipse(ctx, o.x, o.y, 4, 5.4, fill: c.eye)
            }
            ellipse(ctx, o.x + 1.2, o.y + 2, 1.5, 1.5, fill: rgb(0xFFFFFF))
            ellipse(ctx, o.x - 1.3, o.y - 1.9, 0.7, 0.7, fill: rgb(0xFFFFFF, 0.85))
        case .blink:
            ctx.move(to: CGPoint(x: o.x - 4, y: o.y))
            ctx.addLine(to: CGPoint(x: o.x + 4, y: o.y))
            ctx.strokePath()
        case .sleep:
            ctx.move(to: CGPoint(x: o.x - 4, y: o.y + 0.5))
            ctx.addQuadCurve(to: CGPoint(x: o.x + 4, y: o.y + 0.5), control: CGPoint(x: o.x, y: o.y - 3.5))
            ctx.strokePath()
        case .happy:
            ctx.move(to: CGPoint(x: o.x - 4.2, y: o.y - 1.5))
            ctx.addQuadCurve(to: CGPoint(x: o.x + 4.2, y: o.y - 1.5), control: CGPoint(x: o.x, y: o.y + 4.5))
            ctx.strokePath()
        case .wide:
            ellipse(ctx, o.x, o.y, 6.2, 6.2, fill: rgb(0xFFFFFF), stroke: c.outline, lineWidth: 1.6)
            ellipse(ctx, o.x + p.look.x * 1.6, o.y + p.look.y * 1.6, 2.3, 2.3, fill: pupil)
        }
    }

    // MARK: Particles

    static func draw(_ ctx: CGContext, particles: [Particle]) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for q in particles {
            let fade = min(1, (q.life - q.age) / 0.4)
            ctx.saveGState()
            ctx.translateBy(x: q.pos.x, y: q.pos.y)
            ctx.setAlpha(max(0, fade))
            switch q.kind {
            case .heart:
                let s = q.size * min(1, q.age / 0.15 + 0.2)
                ctx.move(to: CGPoint(x: 0, y: -0.5 * s))
                ctx.addCurve(to: CGPoint(x: -0.5 * s, y: 0.12 * s),
                             control1: CGPoint(x: -0.3 * s, y: -0.28 * s), control2: CGPoint(x: -0.5 * s, y: -0.08 * s))
                ctx.addCurve(to: CGPoint(x: 0, y: 0.26 * s),
                             control1: CGPoint(x: -0.5 * s, y: 0.5 * s), control2: CGPoint(x: -0.08 * s, y: 0.5 * s))
                ctx.addCurve(to: CGPoint(x: 0.5 * s, y: 0.12 * s),
                             control1: CGPoint(x: 0.08 * s, y: 0.5 * s), control2: CGPoint(x: 0.5 * s, y: 0.5 * s))
                ctx.addCurve(to: CGPoint(x: 0, y: -0.5 * s),
                             control1: CGPoint(x: 0.5 * s, y: -0.08 * s), control2: CGPoint(x: 0.3 * s, y: -0.28 * s))
                ctx.closePath()
                ctx.setFillColor(rgb(0xFF5C8A))
                ctx.setStrokeColor(rgb(0xB8305A))
                ctx.setLineWidth(1.2)
                ctx.drawPath(using: .fillStroke)
            case .zed:
                let h = q.size * (0.7 + q.age / q.life * 0.8) / 2
                for (color, width) in [(rgb(0x3F4C7A), 3.4), (rgb(0xFFFFFF), 1.5)] as [(CGColor, CGFloat)] {
                    ctx.move(to: CGPoint(x: -h, y: h))
                    ctx.addLine(to: CGPoint(x: h, y: h))
                    ctx.addLine(to: CGPoint(x: -h, y: -h))
                    ctx.addLine(to: CGPoint(x: h, y: -h))
                    ctx.setStrokeColor(color)
                    ctx.setLineWidth(width)
                    ctx.strokePath()
                }
            }
            ctx.restoreGState()
        }
    }

    // MARK: Shape helpers

    private static func ellipse(_ ctx: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat,
                                fill: CGColor, stroke: CGColor? = nil, lineWidth: CGFloat = 0) {
        ctx.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        ctx.setFillColor(fill)
        if let stroke {
            ctx.setStrokeColor(stroke)
            ctx.setLineWidth(lineWidth)
            ctx.drawPath(using: .fillStroke)
        } else {
            ctx.fillPath()
        }
    }

    private static func polygon(_ ctx: CGContext, _ points: [CGPoint]) {
        ctx.addLines(between: points)
        ctx.closePath()
    }
}
