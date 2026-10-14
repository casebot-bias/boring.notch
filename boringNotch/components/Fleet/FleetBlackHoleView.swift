//
//  FleetBlackHoleView.swift
//  boringNotch
//
//  The collapsed notch's black hole: the fleet's work meter, drawn as a spinning
//  accretion disc with Canvas and TimelineView - no image assets.
//

import SwiftUI

// MARK: - Metrics

/// The black hole's design constants: the box it draws in, the fade that carries the row's
/// width, and the scalars that scale with the fleet. Foundation/CoreGraphics only, so tests
/// can pin these numbers without SwiftUI.
enum FleetBlackHoleMetrics {
    static let size: CGFloat = 18
    static let gap: CGFloat = 6
    /// The row's width fade, so the text slides rather than jumping when work starts or stops.
    static let fadeSeconds: Double = 0.3
    static let maxFPS: Double = 30
    static var frameInterval: Double { 1 / maxFPS }
    /// Seconds for the disc's conic sweep to come back round; the spin multiplies it.
    static let turnSeconds: Double = 4
    static let calmSpin: Double = 1
    static let spinPerWorker: Double = 0.2
    static let maxSpin: Double = 2
    static let minParticles = 6
    static let maxParticles = 10
    static let coreFraction: Double = 0.15
    static let ringFraction: Double = 0.185
    static let discMajorFraction: Double = 0.46
    static let discMinorFraction: Double = 0.17
    static let glowFraction: Double = 0.5
    /// The disc tips by this much, so the near half reads as in front of the core.
    static let tiltDegrees: Double = -16

    /// The calm disc gains a fifth of a turn per extra worker, capped: past six workers the
    /// hole is already spinning as fast as it should at this size.
    static func spin(working: Int) -> Double {
        min(maxSpin, calmSpin + spinPerWorker * Double(min(max(working - 1, 0), 5)))
    }

    /// Six dots trail the calm disc, one more per worker, capped at ten.
    static func particleCount(working: Int) -> Int {
        min(maxParticles, minParticles + max(0, working - 1))
    }

    /// The whole hole brightens with the fleet and saturates at 1.25, so five workers' work
    /// still reads brighter than one's without blowing out.
    static func brightness(working: Int) -> Double {
        min(1.25, 1 + 0.05 * Double(min(max(working - 1, 0), 5)))
    }
}

// MARK: - Visibility

/// Whether the row shows the hole, and how hard it spins. The row only builds the view while
/// this says work runs, so nothing ticks while the hole is hidden.
struct FleetBlackHoleState: Equatable {
    let working: Int
    let isVisible: Bool

    static let hidden = FleetBlackHoleState(working: 0, isVisible: false)

    /// The hole shows while anything works, and while only a tool run the case itself started
    /// is alive. A negative count is never work, so it clamps to zero rather than leaking.
    static func resolve(working: Int, toolRuns: [ToolRun]) -> FleetBlackHoleState {
        let workers = max(0, working)
        return FleetBlackHoleState(working: workers, isVisible: workers > 0 || !toolRuns.isEmpty)
    }
}

// MARK: - Particle model

/// One infalling dot: its phase along the disc (0 = the outer edge, 1 = the core), its angle in
/// turns, and how fast it falls relative to the spin. Plain numbers so the tests can step it.
struct FleetBlackHoleParticle: Equatable {
    var phase: Double
    var angle: Double
    var fallRate: Double
}

/// The fall geometry, as pure maths: the radius a phase maps to, one clock step of a particle,
/// and the whole field from the clock alone. No SwiftUI type lives here, so the tests step the
/// same numbers the view draws from.
enum FleetBlackHoleModel {
    static let edgeFraction: Double = 0.45
    static let coreFraction: Double = 0.17
    static let fallSeconds: Double = 2.6
    /// The golden-angle conjugate: each respawn lands the dot on the next irrational slice of
    /// the disc, so the field never clumps.
    static let respawnAngle: Double = 0.6180339887498949

    /// The orbit radius for a phase: the span from the disc's edge to the core, eased by
    /// smoothstep so the fall accelerates then settles. Monotone falling, so a particle only
    /// ever spirals inward.
    static func radius(phase: Double, size: CGFloat) -> CGFloat {
        let t = min(max(phase, 0), 1)
        let eased = t * t * (3 - 2 * t)
        let edge = edgeFraction * size
        let core = coreFraction * size
        return edge + (core - edge) * eased
    }

    /// Advance one particle. A completed fall respawns the dot whole at the edge on the next
    /// golden angle - never a partial wrap - keeping its fall rate.
    static func step(_ particle: FleetBlackHoleParticle, dt: Double, spin: Double) -> FleetBlackHoleParticle {
        let next = particle.phase + dt * spin * particle.fallRate / fallSeconds
        if next >= 1 {
            return FleetBlackHoleParticle(phase: 0,
                                          angle: fract(particle.angle + respawnAngle),
                                          fallRate: particle.fallRate)
        }
        return FleetBlackHoleParticle(phase: next,
                                      angle: particle.angle,
                                      fallRate: particle.fallRate)
    }

    /// The field at `time`, straight from the clock: each dot's phase, angle and fall rate are
    /// closed forms of its index, so no state has to be carried between frames.
    static func field(count: Int, time: Double, spin: Double) -> [FleetBlackHoleParticle] {
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let i = Double(index)
            let fallRate = 1 + 0.45 * fract(i * 0.3183098861837907)
            let angle = fract(i / Double(count) + 0.11 * fract(i * respawnAngle))
            let phase = fract(time * spin * fallRate / fallSeconds + fract(i * respawnAngle))
            return FleetBlackHoleParticle(phase: phase, angle: angle, fallRate: fallRate)
        }
    }

    /// A dot fades as it falls: full at the edge, gone at the core, where the hole swallows it.
    static func brightness(phase: Double) -> Double {
        max(0, 1 - min(max(phase, 0), 1))
    }

    /// The fractional part, always in 0..<1, negative inputs included.
    static func fract(_ value: Double) -> Double {
        value - floor(value)
    }
}

// MARK: - The frozen-time seam

private struct FleetBlackHoleFrozenTimeKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// Pinning the clock draws one still frame: the tests and the docs image pin an instant,
    /// while the live row leaves this nil and the hole animates.
    var fleetBlackHoleFrozenTime: Double? {
        get { self[FleetBlackHoleFrozenTimeKey.self] }
        set { self[FleetBlackHoleFrozenTimeKey.self] = newValue }
    }
}

// MARK: - The hole

/// The closed row's black hole: a tilted, spinning accretion disc around a black core. The
/// clock arrives through `time`: pinned it draws one still frame, otherwise a timeline drives
/// it at no more than 30 fps. The row only builds this view while work runs, so nothing ticks
/// while the row draws no hole.
struct FleetBlackHoleView: View {
    let working: Int
    /// An explicit pin for previews and the docs image; the tests pin through the environment
    /// instead, because the row builds this view without naming the clock.
    var frozenTime: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.fleetBlackHoleFrozenTime) private var environmentFrozenTime

    /// Reduce Motion always draws one still frame at 0, so the runtime never reads a timeline.
    private var time: Double? { reduceMotion ? 0 : frozenTime ?? environmentFrozenTime }

    var body: some View {
        Group {
            if let time {
                FleetBlackHoleFrame(working: working, time: time, showsParticles: !reduceMotion)
            } else {
                // 30 fps is plenty for an 18 pt hole and keeps the notch's redraw cost honest.
                TimelineView(.animation(minimumInterval: FleetBlackHoleMetrics.frameInterval, paused: false)) { timeline in
                    FleetBlackHoleFrame(working: working,
                                        time: timeline.date.timeIntervalSinceReferenceDate,
                                        showsParticles: true)
                }
            }
        }
        .frame(width: FleetBlackHoleMetrics.size, height: FleetBlackHoleMetrics.size)
        .accessibilityHidden(true)
    }
}

/// One drawn frame of the hole at a fixed instant: a single Canvas whose paint order is the
/// illusion - glow, the disc's far half behind the core, the core and its photon ring, then the
/// disc's near half and the infalling dots in front.
private struct FleetBlackHoleFrame: View {
    let working: Int
    let time: Double
    let showsParticles: Bool

    var body: some View {
        Canvas { context, size in
            let spin = FleetBlackHoleMetrics.spin(working: working)
            let light = FleetBlackHoleMetrics.brightness(working: working)
            let turn = FleetBlackHoleModel.fract(time * spin / FleetBlackHoleMetrics.turnSeconds)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2

            // The glow: a box-sized violet haze so the hole reads as hot behind the disc.
            context.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                         with: .radialGradient(Gradient(colors: [FleetBlackHolePalette.violet.opacity(0.30 * light),
                                                                 FleetBlackHolePalette.violet.opacity(0)]),
                                               center: center,
                                               startRadius: 0,
                                               endRadius: radius))

            let major = CGFloat(FleetBlackHoleMetrics.discMajorFraction) * size.width
            let minor = CGFloat(FleetBlackHoleMetrics.discMinorFraction) * size.width
            let disc = Path(ellipseIn: CGRect(x: center.x - major,
                                              y: center.y - minor,
                                              width: major * 2,
                                              height: minor * 2))
            let sweep = GraphicsContext.Shading.conicGradient(
                Gradient(colors: [FleetBlackHolePalette.orange,
                                  FleetBlackHolePalette.pink,
                                  FleetBlackHolePalette.violet,
                                  FleetBlackHolePalette.orange]),
                center: center,
                angle: .radians(turn * 2 * .pi))
            let halfLine = size.height / 2
            let tilt = Angle.degrees(FleetBlackHoleMetrics.tiltDegrees)
            let discStroke = StrokeStyle(lineWidth: 1)

            // The disc's far half, dimmed and clipped above the middle: it passes behind the core.
            // Clip before the tilt so the clip line stays the horizon, not a tilted chord.
            context.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: halfLine)))
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: tilt)
                layer.translateBy(x: -center.x, y: -center.y)
                layer.opacity = 0.45 * light
                layer.stroke(disc, with: sweep, style: discStroke)
            }

            // The core: a black disc the glow and the far half cannot cross.
            let coreRadius = CGFloat(FleetBlackHoleMetrics.coreFraction) * size.width
            let core = Path(ellipseIn: CGRect(x: center.x - coreRadius,
                                              y: center.y - coreRadius,
                                              width: coreRadius * 2,
                                              height: coreRadius * 2))
            context.fill(core, with: .color(.black))

            // The photon ring: the hairline of light bent around the core's edge.
            context.stroke(core,
                           with: .color(FleetBlackHolePalette.ring.opacity(0.9 * light)),
                           style: StrokeStyle(lineWidth: 0.6))

            // The disc's near half, at full colour in front of the core...
            context.drawLayer { layer in
                layer.clip(to: Path(CGRect(x: 0, y: center.y, width: size.width, height: halfLine)))
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: tilt)
                layer.translateBy(x: -center.x, y: -center.y)
                layer.stroke(disc, with: sweep, style: discStroke)

                // ... and the Doppler pass: the approaching (left) side burns whiter.
                var doppler = layer
                doppler.opacity = 0.5 * light
                doppler.stroke(disc,
                               with: .linearGradient(Gradient(colors: [Color.white.opacity(0.5 * light),
                                                                      Color.white.opacity(0)]),
                                                     startPoint: CGPoint(x: 0, y: center.y),
                                                     endPoint: center),
                               style: discStroke)
            }

            // The infalling dots, in the disc's own plane, faded by how far they have fallen.
            guard showsParticles else { return }
            let flat = CGFloat(FleetBlackHoleMetrics.discMinorFraction / FleetBlackHoleMetrics.discMajorFraction)
            let particles = FleetBlackHoleModel.field(count: FleetBlackHoleMetrics.particleCount(working: working),
                                                      time: time,
                                                      spin: spin)
            context.drawLayer { layer in
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: tilt)
                layer.translateBy(x: -center.x, y: -center.y)
                for particle in particles {
                    let r = FleetBlackHoleModel.radius(phase: particle.phase, size: size.width)
                    let theta = particle.angle * 2 * .pi
                    let x = center.x + r * CGFloat(cos(theta))
                    let y = center.y + r * CGFloat(sin(theta)) * flat
                    let dotRadius = CGFloat(0.28 + 0.22 * FleetBlackHoleModel.brightness(phase: particle.phase))
                    layer.fill(Path(ellipseIn: CGRect(x: x - dotRadius,
                                                      y: y - dotRadius,
                                                      width: dotRadius * 2,
                                                      height: dotRadius * 2)),
                               with: .color(FleetBlackHolePalette.pink.opacity(0.85 * FleetBlackHoleModel.brightness(phase: particle.phase))))
                }
            }
        }
    }
}

/// The hole's fixed colours: the hot side of an accretion disc - orange through pink to violet -
/// and the cream photon ring. Hex literals, so the design and the file hold one source.
private enum FleetBlackHolePalette {
    static let orange = Color(red: 0xFF / 255, green: 0x9A / 255, blue: 0x3C / 255)
    static let pink = Color(red: 0xFF / 255, green: 0x5A / 255, blue: 0x8A / 255)
    static let violet = Color(red: 0xA9 / 255, green: 0x6C / 255, blue: 0xFF / 255)
    static let ring = Color(red: 0xFF / 255, green: 0xE9 / 255, blue: 0xD2 / 255)
}
