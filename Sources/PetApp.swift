import AppKit
import QuartzCore

// The app shell: a transparent floating window that follows the pet around,
// mouse handling, and the menu.

final class PetView: NSView {
    weak var controller: PetController?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let controller else { return }
        let pet = controller.pet
        ctx.scaleBy(x: pet.scale, y: pet.scale)
        PetArt.draw(ctx, pose: pet.pose(), facing: pet.facing, coat: controller.coat)
        PetArt.draw(ctx, particles: pet.particles)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showMenu(event)
        } else {
            controller?.pressBegan()
        }
    }

    override func mouseUp(with event: NSEvent) { controller?.pressEnded() }
    override func rightMouseDown(with event: NSEvent) { showMenu(event) }

    private func showMenu(_ event: NSEvent) {
        guard let menu = controller?.menu else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class PetController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let sizes: [(name: String, scale: CGFloat)] = [("Small", 0.7), ("Medium", 1.0), ("Large", 1.4)]

    let pet = Pet()
    let menu = NSMenu()
    var coat: Coat { Coat.all[coatIndex] }

    private var window: NSPanel!
    private var view: PetView!
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var frame = 0

    private var pressing = false
    private var dragging = false
    private var pressStart = 0.0
    private var pressOrigin = CGPoint.zero
    private var grabOffset = CGVector.zero

    private var coatIndex = 0
    private var sizeIndex = 1
    private var napItem: NSMenuItem!
    private var chaseItem: NSMenuItem!
    private var coatItems: [NSMenuItem] = []
    private var sizeItems: [NSMenuItem] = []

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        coatIndex = min(max(defaults.integer(forKey: "coat"), 0), Coat.all.count - 1)
        sizeIndex = min(max(defaults.object(forKey: "size") as? Int ?? 1, 0), Self.sizes.count - 1)
        pet.chaseCursor = defaults.bool(forKey: "chase")
        pet.scale = Self.sizes[sizeIndex].scale
        pet.world = { point in
            let screens = NSScreen.screens
            func gap(_ screen: NSScreen) -> CGFloat {
                let f = screen.frame
                return hypot(max(f.minX - point.x, 0, point.x - f.maxX), max(f.minY - point.y, 0, point.y - f.maxY))
            }
            guard let home = screens.min(by: { gap($0) < gap($1) }) else {
                return World(floor: 0, left: 0, right: 1440, top: 900)
            }
            return World(floor: home.visibleFrame.minY,
                         left: screens.map { $0.visibleFrame.minX }.min() ?? home.visibleFrame.minX,
                         right: screens.map { $0.visibleFrame.maxX }.max() ?? home.visibleFrame.maxX,
                         top: home.frame.maxY)
        }

        // Drop in from the top of the main screen.
        if let screen = NSScreen.main {
            pet.pos = CGPoint(x: screen.visibleFrame.midX + .random(in: -200...200),
                              y: screen.frame.maxY - 100 * pet.scale)
        }

        window = NSPanel(contentRect: NSRect(origin: .zero, size: windowSize),
                         styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Flat cartoon colors don't need the display's deep-color backing store,
        // and 8-bit drawing is much cheaper.
        window.depthLimit = .twentyfourBitRGB
        window.colorSpace = .sRGB
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        view = PetView(frame: NSRect(origin: .zero, size: windowSize))
        view.controller = self
        window.contentView = view
        syncWindow()
        window.orderFrontRegardless()

        buildMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Desktop Pet")
        statusItem.menu = menu

        let timer = Timer(timeInterval: 1.0 / 60, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 1.0 / 240
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private var windowSize: CGSize {
        CGSize(width: PetArt.canvas.width * pet.scale, height: PetArt.canvas.height * pet.scale)
    }

    private func syncWindow() {
        let origin = CGPoint(x: pet.pos.x - PetArt.origin.x * pet.scale, y: pet.pos.y - PetArt.origin.y * pet.scale)
        if window.frame.origin != origin { window.setFrameOrigin(origin) }
    }

    // MARK: Frame loop

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(now - lastTick, 1.0 / 20))
        lastTick = now
        let cursor = NSEvent.mouseLocation

        if pressing {
            if NSEvent.pressedMouseButtons & 1 == 0 {
                pressEnded()
            } else if !dragging {
                let moved = hypot(cursor.x - pressOrigin.x, cursor.y - pressOrigin.y)
                if moved > 4 || now - pressStart > 0.22 {
                    dragging = true
                    pet.grab()
                }
            }
        }
        if dragging {
            // Ease the scruff up under the cursor so the pet hangs from it.
            let ease = 1 - exp(-dt * 16)
            grabOffset.dx += (0 - grabOffset.dx) * ease
            grabOffset.dy += (-PetArt.grab.y * pet.scale - grabOffset.dy) * ease
            pet.pos = CGPoint(x: cursor.x + grabOffset.dx, y: cursor.y + grabOffset.dy)
        }

        let hovering = pet.hitTest(cursor)
        pet.tick(dt: dt, cursor: cursor, hovering: hovering && !pressing)

        // Clicks only land on the pet itself; everywhere else they pass through.
        let ignore = !(pressing || hovering)
        if window.ignoresMouseEvents != ignore { window.ignoresMouseEvents = ignore }

        syncWindow()
        frame += 1
        if frame % pet.frameStride == 0 { view.needsDisplay = true }
    }

    // MARK: Mouse

    func pressBegan() {
        let cursor = NSEvent.mouseLocation
        pressing = true
        dragging = false
        pressStart = CACurrentMediaTime()
        pressOrigin = cursor
        grabOffset = CGVector(dx: pet.pos.x - cursor.x, dy: pet.pos.y - cursor.y)
    }

    func pressEnded() {
        guard pressing else { return }
        if dragging {
            pet.release()
        } else {
            pet.poke()
        }
        pressing = false
        dragging = false
    }

    // MARK: Menu

    private func buildMenu() {
        menu.delegate = self
        menu.addItem(item("Come Here", #selector(comeHere)))
        napItem = item("Take a Nap", #selector(toggleNap))
        menu.addItem(napItem)
        chaseItem = item("Chase the Cursor", #selector(toggleChase))
        menu.addItem(chaseItem)
        menu.addItem(.separator())

        let coatMenu = NSMenu()
        for (index, coat) in Coat.all.enumerated() {
            let entry = item(coat.name, #selector(pickCoat(_:)))
            entry.tag = index
            coatItems.append(entry)
            coatMenu.addItem(entry)
        }
        let coatParent = NSMenuItem(title: "Coat", action: nil, keyEquivalent: "")
        coatParent.submenu = coatMenu
        menu.addItem(coatParent)

        let sizeMenu = NSMenu()
        for (index, size) in Self.sizes.enumerated() {
            let entry = item(size.name, #selector(pickSize(_:)))
            entry.tag = index
            sizeItems.append(entry)
            sizeMenu.addItem(entry)
        }
        let sizeParent = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeParent.submenu = sizeMenu
        menu.addItem(sizeParent)

        menu.addItem(.separator())
        menu.addItem(item("Quit Desktop Pet", #selector(quit)))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        return entry
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        napItem.title = pet.mood == .sleep ? "Wake Up" : "Take a Nap"
        chaseItem.state = pet.chaseCursor ? .on : .off
        for entry in coatItems { entry.state = entry.tag == coatIndex ? .on : .off }
        for entry in sizeItems { entry.state = entry.tag == sizeIndex ? .on : .off }
    }

    @objc private func comeHere() { pet.summon(toX: NSEvent.mouseLocation.x) }
    @objc private func toggleNap() { pet.toggleNap() }

    @objc private func toggleChase() {
        pet.chaseCursor.toggle()
        UserDefaults.standard.set(pet.chaseCursor, forKey: "chase")
    }

    @objc private func pickCoat(_ sender: NSMenuItem) {
        coatIndex = sender.tag
        UserDefaults.standard.set(coatIndex, forKey: "coat")
        view.needsDisplay = true
    }

    @objc private func pickSize(_ sender: NSMenuItem) {
        sizeIndex = sender.tag
        UserDefaults.standard.set(sizeIndex, forKey: "size")
        pet.scale = Self.sizes[sizeIndex].scale
        window.setContentSize(windowSize)
        syncWindow()
        view.needsDisplay = true
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
