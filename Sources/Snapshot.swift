import AppKit

// Renders the pet to PNG files without opening a window:
//   DesktopPet --poses out.png   every mood, for every coat
//   DesktopPet --icon out.png    the 1024 px app icon

enum Snapshot {
    static func png(width: Int, height: Int, draw: (CGContext) -> Void) -> Data? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        draw(ctx)
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func writePoses(to path: String, zoom: CGFloat = 1.5) -> Bool {
        let setups: [(Pet) -> Void] = [
            { $0.mood = .idle },
            { $0.mood = .walk; $0.walkPhase = 0.9 },
            { $0.mood = .run; $0.walkPhase = 4.2 },
            { $0.mood = .sleep; $0.particles = [zed(0.4), zed(1.4)] },
            { $0.mood = .held; $0.swing = -0.35 },
            { $0.mood = .fall },
            { $0.mood = .land; $0.moodTime = 0.02 },
            { $0.mood = .happy; $0.moodTime = 0.18; $0.particles = [heart(-16, 0.3), heart(4, 0.7), heart(20, 0.5)] },
            { $0.mood = .startled; $0.moodTime = 0.15 },
        ]
        let cell = PetArt.canvas
        let width = Int(cell.width * zoom) * setups.count
        let height = Int(cell.height * zoom) * Coat.all.count
        let data = png(width: width, height: height) { ctx in
            for (row, coat) in Coat.all.enumerated() {
                for (column, setup) in setups.enumerated() {
                    let pet = Pet()
                    pet.clock = 1
                    pet.facing = column % 2 == 0 ? 1 : -1
                    setup(pet)
                    ctx.saveGState()
                    ctx.translateBy(x: CGFloat(column) * cell.width * zoom,
                                    y: CGFloat(Coat.all.count - 1 - row) * cell.height * zoom)
                    ctx.scaleBy(x: zoom, y: zoom)
                    let light = (row + column) % 2 == 0
                    ctx.setFillColor(CGColor(srgbRed: light ? 0.62 : 0.24, green: light ? 0.70 : 0.29,
                                             blue: light ? 0.78 : 0.38, alpha: 1))
                    ctx.fill(CGRect(origin: .zero, size: cell))
                    PetArt.draw(ctx, pose: pet.pose(), facing: pet.facing, coat: coat)
                    PetArt.draw(ctx, particles: pet.particles)
                    ctx.restoreGState()
                }
            }
        }
        return write(data, to: path)
    }

    static func writeIcon(to path: String) -> Bool {
        let data = png(width: 1024, height: 1024) { ctx in
            let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil))
            ctx.clip()
            let colors = [CGColor(srgbRed: 0.72, green: 0.90, blue: 0.98, alpha: 1),
                          CGColor(srgbRed: 0.45, green: 0.72, blue: 0.93, alpha: 1)] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.minY), options: [])
            }
            let zoom: CGFloat = 6.4
            ctx.translateBy(x: 512 - PetArt.origin.x * zoom + 20, y: 235 - PetArt.origin.y * zoom)
            ctx.scaleBy(x: zoom, y: zoom)
            let pet = Pet()
            pet.mood = .idle
            pet.clock = 1
            PetArt.draw(ctx, pose: pet.pose(), facing: 1, coat: Coat.all[0])
            ctx.restoreGState()
        }
        return write(data, to: path)
    }

    private static func write(_ data: Data?, to path: String) -> Bool {
        guard let data else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    private static func heart(_ x: CGFloat, _ age: CGFloat) -> Particle {
        Particle(kind: .heart, pos: CGPoint(x: PetArt.origin.x + x, y: PetArt.origin.y + 92 + age * 30),
                 vel: .zero, life: 1.4, size: 12, wobble: 0, age: age)
    }

    private static func zed(_ age: CGFloat) -> Particle {
        Particle(kind: .zed, pos: CGPoint(x: PetArt.origin.x - 24 - age * 7, y: PetArt.origin.y + 56 + age * 16),
                 vel: .zero, life: 2.4, size: 6, wobble: 0, age: age)
    }
}
