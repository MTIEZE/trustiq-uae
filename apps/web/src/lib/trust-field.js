/**
 * The hero's field: points that meet, hold, and settle into agreements.
 *
 * The simulation and the drawing live here, apart from the React component, so
 * that both can be driven a step at a time by something other than a display.
 * That is not a hypothetical: the thing renders on a clock, and a clock is
 * exactly what a headless check does not have.
 *
 * Nothing in here touches the DOM beyond the context it is handed.
 */

/** How long two points must stay in reach before the line between them seals. */
export const SEAL_MS = 1400
/** And how long a broken one takes to let go. Slower than it formed, on purpose. */
export const FADE_MS = 2200

export function parseHex(hex) {
  const h = String(hex).trim().replace('#', '')
  const n = parseInt(h.length === 3 ? h.replace(/./g, (c) => c + c) : h, 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

export function createField(ctx, { width, height, modest = false, random = Math.random }) {
  let w = width
  let h = height
  let nodes = []
  let bonds = new Map()
  let accent = [13, 95, 102]
  let faint = [124, 136, 144]

  function populate() {
    // Density has to beat reach or nothing ever meets. At the first numbers
    // the average gap between points was wider than the distance at which two
    // of them can see each other, so on a narrow window the field was a dozen
    // dots that never found anybody.
    const target = Math.round((w * h) / 14000)
    const count = Math.max(12, Math.min(modest ? 24 : 46, modest ? target >> 1 : target))
    nodes = []
    bonds = new Map()
    for (let i = 0; i < count; i += 1) {
      const a = random() * Math.PI * 2
      const speed = 0.06 + random() * 0.07
      nodes.push({
        x: random() * w,
        y: random() * h,
        vx: Math.cos(a) * speed,
        vy: Math.sin(a) * speed,
        // Staggered, so the field assembles rather than switching on.
        in: -random() * 1.4,
        r: 1.8 + random() * 1.8,
      })
    }
  }

  // Local rather than sprawling. At the wider reach the field tried, most
  // pairs sat near the limit, every line came out at the faint end of the
  // falloff, and the whole thing measured as drawn and read as blank.
  const reach = () => Math.max(110, Math.min(190, Math.min(w, h) * 0.24))

  function step(dt) {
    const R = reach()
    for (const n of nodes) {
      if (n.in < 1) n.in = Math.min(1, n.in + dt / 900)
      n.x += n.vx * dt * 0.06
      n.y += n.vy * dt * 0.06
      if (n.x < -20) n.x = w + 20
      if (n.x > w + 20) n.x = -20
      if (n.y < -20) n.y = h + 20
      if (n.y > h + 20) n.y = -20
    }

    const seen = new Set()
    for (let i = 0; i < nodes.length; i += 1) {
      for (let j = i + 1; j < nodes.length; j += 1) {
        const a = nodes[i]
        const b = nodes[j]
        const dx = a.x - b.x
        const dy = a.y - b.y
        const d2 = dx * dx + dy * dy
        if (d2 > R * R) continue
        const key = i * 1000 + j
        seen.add(key)
        const bond = bonds.get(key) ?? { i, j, t: 0, sealed: 0, d: R }
        bond.t = Math.min(1, bond.t + dt / SEAL_MS)
        bond.d = Math.sqrt(d2)
        if (bond.t >= 1 && !bond.sealed) bond.sealed = 1
        bonds.set(key, bond)
      }
    }
    for (const [key, bond] of bonds) {
      if (seen.has(key)) continue
      // The distance has to be recomputed while a bond lets go, not left at
      // whatever it was when the pair was last in reach. Left stale, a bond
      // formed at fifty pixels kept drawing at fifty pixels' worth of weight
      // while its two ends drifted a thousand apart, which put a hard line
      // straight across the hero for two seconds at a time.
      const a = nodes[bond.i]
      const b = nodes[bond.j]
      if (!a || !b) {
        bonds.delete(key)
        continue
      }
      bond.d = Math.hypot(a.x - b.x, a.y - b.y)
      // And a point that wrapped round the edge did not drift anywhere. It
      // teleported, and the line it was holding has to go at once.
      if (bond.d > reach() * 1.5) {
        bonds.delete(key)
        continue
      }
      bond.t -= dt / FADE_MS
      if (bond.t <= 0) bonds.delete(key)
    }
  }

  function draw() {
    const R = reach()
    ctx.clearRect(0, 0, w, h)

    for (const bond of bonds.values()) {
      const a = nodes[bond.i]
      const b = nodes[bond.j]
      if (!a || !b) continue
      // Two things gate a line: how long the pair has held, and how close they
      // are. A line at the very edge of reach stays a hairline. The curve is
      // bent because a straight one puts almost every pair near zero: in a
      // scattered field, most of the pairs inside a radius sit near its edge.
      const near = Math.pow(Math.max(0, 1 - bond.d / R), 0.6)
      const strength = bond.t * near
      if (strength < 0.02) continue
      const fade = Math.max(0, a.in) * Math.max(0, b.in)
      const alpha = strength * (bond.sealed ? 0.92 : 0.46) * fade
      ctx.strokeStyle = 'rgba(' + accent[0] + ',' + accent[1] + ',' + accent[2] + ',' + alpha + ')'
      // A sealed line is heavier than a tentative one. Under a pixel, both
      // came out as the same grey suggestion of a line.
      ctx.lineWidth = bond.sealed ? 1.45 : 0.9
      ctx.beginPath()
      ctx.moveTo(a.x, a.y)
      ctx.lineTo(b.x, b.y)
      ctx.stroke()

      if (bond.sealed && bond.t > 0.6) {
        // The agreement: a small mark where the two met, set on its corner so it
        // reads as a seal rather than as another point in the field.
        const s = 3.2 * strength
        ctx.save()
        ctx.translate((a.x + b.x) / 2, (a.y + b.y) / 2)
        ctx.rotate(Math.PI / 4)
        ctx.strokeStyle =
          'rgba(' + accent[0] + ',' + accent[1] + ',' + accent[2] + ',' + strength * 0.85 * fade + ')'
        ctx.lineWidth = 1
        ctx.strokeRect(-s, -s, s * 2, s * 2)
        ctx.restore()
      }
    }

    for (const n of nodes) {
      if (n.in <= 0) continue
      const eased = n.in * n.in
      ctx.fillStyle = 'rgba(' + faint[0] + ',' + faint[1] + ',' + faint[2] + ',' + 0.78 * eased + ')'
      ctx.beginPath()
      ctx.arc(n.x, n.y, n.r, 0, Math.PI * 2)
      ctx.fill()
    }
  }

  populate()

  return {
    step,
    draw,
    palette(a, f) {
      accent = a
      faint = f
    },
    resize(nw, nh) {
      w = nw
      h = nh
      populate()
    },
    /** Wind forward and paint the one frame it lands on: a composed still. */
    settle(steps = 260) {
      for (let i = 0; i < steps; i += 1) step(16)
      draw()
    },
    get state() {
      return { nodes, bonds }
    },
  }
}
