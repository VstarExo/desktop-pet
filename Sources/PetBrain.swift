import AppKit

// The pet's simulation: what it is doing, where it is, and how it moves.
// Positions are in screen points; `pos` is the point between the pet's feet.

enum Mood { case idle, walk, run, sleep, held, fall, land, happy, startled }
enum EyeStyle { case open, blink, sleep, happy, wide }
enum MouthStyle { case smile, grin, open }
enum TailStyle { case up, hang, wrap }

/// Everything the artist needs to draw one frame, in design units.
struct Pose {
    var sx: CGFloat = 1, sy: CGFloat = 1          // whole-pet squash and stretch
    var bodySX: CGFloat = 1, bodySY: CGFloat = 1  // body only (the sleeping loaf)
    var lift: CGFloat = 0                          // height off the ground
    var rotation: CGFloat = 0                      // swing around the scruff
    var lean: CGFloat = 0                          // tilt around the feet
    var headDX: CGFloat = 0, headDY: CGFloat = 0, headTilt: CGFloat = 0
    var footA = CGPoint.zero, footB = CGPoint.zero
    var tail = TailStyle.up
    var tailSway: CGFloat = 0
    var eyes = EyeStyle.open
    var mouth = MouthStyle.smile
    var look = CGPoint.zero
    var shadow: CGFloat = 1
}

struct Particle {
    enum Kind { case heart, zed }
    var kind: Kind
    var pos: CGPoint
    var vel: CGVector
    var life: CGFloat
    var size: CGFloat
    var wobble: CGFloat
    var age: CGFloat = 0
}

/// The edges the pet can stand on and bump into.
struct World {
    var floor: CGFloat
    var left: CGFloat
    var right: CGFloat
    var top: CGFloat
}

final class Pet {
    var pos = CGPoint.zero
    var vel = CGVector.zero
    var facing: CGFloat = 1
    var scale: CGFloat = 1
    var chaseCursor = false
    var mood = Mood.fall
    var moodTime: CGFloat = 0
    var moodDuration: CGFloat = 0
    var clock: CGFloat = 0
    var walkPhase: CGFloat = 0
    var swing: CGFloat = 0
    var particles: [Particle] = []
    var world: (CGPoint) -> World = { _ in World(floor: 0, left: 0, right: 1440, top: 900) }

    private var targetX: CGFloat = 0
    private var summoned = false
    private var swingVel: CGFloat = 0
    private var holdVel = CGVector.zero
    private var prevPos = CGPoint.zero
    private var nextBlink: CGFloat = 2
    private var blinkUntil: CGFloat = 0
    private var look = CGPoint.zero
    private var nextZed: CGFloat = 0
    private var rub: CGFloat = 0
    private var lastCursor = CGPoint.zero
    private var cheerCooldown: CGFloat = 0

    var grounded: Bool { mood != .held && mood != .fall }

    /// Redraw every Nth tick of the 60 Hz loop: fast action gets every frame,
    /// a stroll gets 30 fps, and sitting or sleeping gets 15 fps to save power.
    var frameStride: Int {
        switch mood {
        case .idle, .sleep: return particles.isEmpty ? 4 : 2
        case .walk: return 2
        default: return 1
        }
    }

    // MARK: Things you can do to the pet

    func grab() {
        enter(.held)
        holdVel = .zero
        prevPos = pos
        summoned = false
    }

    func release() {
        var v = holdVel
        let speed = hypot(v.dx, v.dy)
        let cap: CGFloat = 3200
        if speed > cap {
            v.dx *= cap / speed
            v.dy *= cap / speed
        }
        vel = v
        enter(.fall)
    }

    func poke() {
        if mood == .sleep {
            enter(.startled, for: 0.8)
        } else if grounded {
            cheer()
        }
    }

    func summon(toX x: CGFloat) {
        guard grounded else { return }
        targetX = x
        summoned = true
        enter(.run)
    }

    func toggleNap() {
        if mood == .sleep {
            enter(.startled, for: 0.8)
        } else if grounded {
            enter(.sleep, for: .random(in: 45...90))
        }
    }

    func cheer(hearts: Bool = true) {
        enter(.happy, for: hearts ? 1.5 : 0.9)
        cheerCooldown = 2.5
        guard hearts else { return }
        for _ in 0..<3 {
            particles.append(Particle(
                kind: .heart,
                pos: CGPoint(x: PetArt.origin.x + .random(in: -24...24),
                             y: PetArt.origin.y + .random(in: 74...88)),
                vel: CGVector(dx: .random(in: -7...7), dy: .random(in: 22...34)),
                life: .random(in: 1.1...1.5),
                size: .random(in: 9...13),
                wobble: .random(in: 0...6)))
        }
    }

    /// Is this screen point on the pet's head or body?
    func hitTest(_ p: CGPoint) -> Bool {
        let x = (p.x - pos.x) / scale
        let y = (p.y - pos.y) / scale
        let asleep = mood == .sleep
        let hx = x - (asleep ? 7 * facing : 0)
        let hy = y - (asleep ? 36 : 53)
        let inHead = (hx * hx) / (30 * 30) + (hy * hy) / (30 * 30) <= 1
        let by = y - 16
        let inBody = (x * x) / (27 * 27) + (by * by) / (21 * 21) <= 1
        return inHead || inBody
    }

    // MARK: Simulation

    func tick(dt: CGFloat, cursor: CGPoint, hovering: Bool) {
        clock += dt
        moodTime += dt
        cheerCooldown -= dt

        if clock > nextBlink {
            blinkUntil = clock + 0.13
            nextBlink = clock + .random(in: 2.2...6)
        }

        // Eyes follow the cursor.
        let dx = cursor.x - pos.x
        let dy = cursor.y - (pos.y + PetArt.headY * scale)
        let dist = max(1, hypot(dx, dy))
        let reach = min(1, dist / (140 * scale))
        let ease = 1 - exp(-dt * 10)
        look.x += (dx / dist * reach - look.x) * ease
        look.y += (dy / dist * reach - look.y) * ease

        // Rubbing the cursor back and forth over the pet counts as petting.
        rub = max(0, rub - dt * 140)
        if hovering && grounded {
            rub += hypot(cursor.x - lastCursor.x, cursor.y - lastCursor.y)
            if rub > 260 * scale && cheerCooldown <= 0 {
                rub = 0
                cheer()
            }
        }
        lastCursor = cursor

        updateParticles(dt)

        let w = world(pos)
        let half = 28 * scale

        switch mood {
        case .held:
            let step = max(dt, 1 / 240)
            let v = CGVector(dx: (pos.x - prevPos.x) / step, dy: (pos.y - prevPos.y) / step)
            holdVel.dx += (v.dx - holdVel.dx) * 0.3
            holdVel.dy += (v.dy - holdVel.dy) * 0.3
            let target = min(0.75, max(-0.75, -holdVel.dx * 0.0008))
            swingVel += ((target - swing) * 90 - swingVel * 8) * dt
            swing += swingVel * dt

        case .fall:
            vel.dy -= 2600 * dt
            pos.x += vel.dx * dt
            pos.y += vel.dy * dt
            swingVel += (-swing * 90 - swingVel * 8) * dt
            swing += swingVel * dt
            if pos.x < w.left + half {
                pos.x = w.left + half
                vel.dx = abs(vel.dx) * 0.55
            }
            if pos.x > w.right - half {
                pos.x = w.right - half
                vel.dx = -abs(vel.dx) * 0.55
            }
            let headroom = 86 * scale
            if vel.dy > 0 && pos.y + headroom > w.top {
                pos.y = w.top - headroom
                vel.dy = -vel.dy * 0.3
            }
            if pos.y <= w.floor {
                pos.y = w.floor
                if vel.dy < -900 {
                    vel.dy = -vel.dy * 0.32
                    vel.dx *= 0.6
                } else {
                    vel = .zero
                    swing = 0
                    swingVel = 0
                    enter(.land, for: 0.45)
                }
            }

        default:
            // On the ground. If the ground moved (Dock resized, display changed), follow it.
            if pos.y > w.floor + 2 {
                vel = .zero
                enter(.fall)
                break
            }
            pos.y = w.floor
            pos.x = min(max(pos.x, w.left + half), w.right - half)
            groundTick(dt: dt, cursor: cursor, world: w, half: half)
        }

        prevPos = pos
    }

    private func groundTick(dt: CGFloat, cursor: CGPoint, world w: World, half: CGFloat) {
        switch mood {
        case .idle:
            if chaseCursor && abs(cursor.x - pos.x) > 110 * scale {
                targetX = cursor.x
                enter(.run)
            } else if moodTime > moodDuration {
                chooseNext(world: w, half: half)
            }

        case .walk, .run:
            let running = mood == .run
            let chasing = running && chaseCursor && !summoned
            if chasing { targetX = cursor.x }
            targetX = min(max(targetX, w.left + half), w.right - half)
            let speed = (running ? 260 : 58) * scale
            let gap = targetX - pos.x
            let closeEnough = speed * dt + (chasing ? 40 * scale : 0)
            if abs(gap) <= closeEnough {
                if !chasing { pos.x = targetX }
                summoned = false
                enter(.idle, for: .random(in: 1.5...4))
            } else {
                facing = gap > 0 ? 1 : -1
                pos.x += facing * speed * dt
                walkPhase += dt * (running ? 17 : 9.5)
            }

        case .sleep:
            if clock > nextZed {
                nextZed = clock + 1.3
                particles.append(Particle(
                    kind: .zed,
                    pos: CGPoint(x: PetArt.origin.x + facing * 24, y: PetArt.origin.y + 56),
                    vel: CGVector(dx: facing * 7, dy: 16),
                    life: 2.4,
                    size: 6,
                    wobble: .random(in: 0...6)))
            }
            if moodTime > moodDuration { enter(.idle, for: .random(in: 2...4)) }

        case .land, .happy, .startled:
            if moodTime > moodDuration { enter(.idle, for: .random(in: 1.5...4)) }

        case .held, .fall:
            break
        }
    }

    private func chooseNext(world w: World, half: CGFloat) {
        let roll = CGFloat.random(in: 0..<1)
        if chaseCursor {
            if roll < 0.12 {
                enter(.sleep, for: .random(in: 12...30))
            } else {
                enter(.idle, for: .random(in: 2...6))
            }
        } else if roll < 0.55 {
            let stroll = CGFloat.random(in: 80...420) * scale * (Bool.random() ? 1 : -1)
            var target = pos.x + stroll
            if target < w.left + half || target > w.right - half { target = pos.x - stroll }
            targetX = min(max(target, w.left + half), w.right - half)
            enter(.walk)
        } else if roll < 0.68 {
            enter(.sleep, for: .random(in: 15...45))
        } else if roll < 0.80 {
            cheer(hearts: false)
        } else {
            enter(.idle, for: .random(in: 2...6))
        }
    }

    private func enter(_ next: Mood, for duration: CGFloat = 0) {
        mood = next
        moodTime = 0
        moodDuration = duration
        if next == .sleep { nextZed = clock + 0.6 }
    }

    private func updateParticles(_ dt: CGFloat) {
        guard !particles.isEmpty else { return }
        for i in particles.indices {
            particles[i].age += dt
            particles[i].pos.x += (particles[i].vel.dx + sin(particles[i].age * 4 + particles[i].wobble) * 8) * dt
            particles[i].pos.y += particles[i].vel.dy * dt
        }
        particles.removeAll { $0.age >= $0.life }
    }

    // MARK: Pose

    func pose() -> Pose {
        var p = Pose()
        p.look = CGPoint(x: look.x * facing, y: look.y)
        p.eyes = clock < blinkUntil ? .blink : .open
        p.tailSway = sin(clock * 1.7)

        switch mood {
        case .idle:
            let breath = sin(clock * 2.2)
            p.bodySY = 1 + 0.018 * breath
            p.bodySX = 1 - 0.01 * breath

        case .walk, .run:
            let running = mood == .run
            let stride: CGFloat = running ? 6 : 4
            let step: CGFloat = running ? 6.5 : 4.5
            p.footA = CGPoint(x: cos(walkPhase) * stride, y: max(0, -sin(walkPhase)) * step)
            p.footB = CGPoint(x: -cos(walkPhase) * stride, y: max(0, sin(walkPhase)) * step)
            p.lift = abs(sin(walkPhase)) * (running ? 3.5 : 1.5)
            p.lean = running ? -0.13 : -0.04
            p.headDX = running ? 5 : 3
            p.tailSway = sin(walkPhase) * 0.7
            p.look = CGPoint(x: max(p.look.x, 0.5), y: p.look.y * 0.5)
            if running { p.mouth = .grin }

        case .sleep:
            let breath = sin(clock * 1.3)
            p.bodySX = 1.2 + 0.015 * breath
            p.bodySY = 0.72 + 0.03 * breath
            p.headDX = 7
            p.headDY = -17 + 0.8 * breath
            p.headTilt = -0.1
            p.eyes = .sleep
            p.tail = .wrap
            p.tailSway = 0
            p.look = .zero

        case .held, .fall:
            let held = mood == .held
            let kick = sin(clock * 11) * 1.5
            p.rotation = swing
            p.sx = 0.93
            p.sy = 1.1
            p.footA = CGPoint(x: (held ? -1 : -3) + kick, y: held ? -4 : 0)
            p.footB = CGPoint(x: (held ? 1 : 3) - kick, y: held ? -4 : 0)
            p.eyes = .wide
            p.mouth = .open
            p.tail = .hang
            p.tailSway = sin(clock * 6) * 0.6
            p.shadow = 0

        case .land:
            let bounce = exp(-moodTime * 9) * cos(moodTime * 24)
            p.sy = 1 - 0.3 * bounce
            p.sx = 1 + 0.24 * bounce
            if moodTime < 0.18 { p.eyes = .blink }

        case .happy:
            let fade = max(0, 1 - moodTime / 1.3)
            p.lift = abs(sin(moodTime * 9)) * 6 * fade
            p.headTilt = 0.06 * sin(moodTime * 9)
            p.eyes = .happy
            p.mouth = .grin
            p.tailSway = sin(clock * 9)
            p.look = .zero

        case .startled:
            if moodTime < 0.3 { p.lift = sin(moodTime / 0.3 * .pi) * 9 }
            p.eyes = .wide
            p.mouth = .open
        }
        return p
    }
}
