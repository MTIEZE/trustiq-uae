import { useEffect, useRef } from 'react'
import { reducedMotion, modestDevice } from '../lib/motion.js'
import { createField, parseHex } from '../lib/trust-field.js'

/**
 * The hero's background: two parties finding each other and settling on terms.
 *
 * The brief asked for a premium video here. This is a canvas instead, and the
 * choice is deliberate rather than a shortcut.
 *
 * Stock footage of "abstract digital connection" is the exact register the
 * brief rules out everywhere else, it arrives as several megabytes on a page
 * whose whole argument is that it is careful, it is fixed to one colour scheme
 * on a site that follows the device, and it means nothing: the shapes moving
 * are not the product. What is drawn below is. Points appear, drift, come
 * within reach of each other, hold a tentative line while they stay in reach,
 * and at the moment that line has held long enough it seals into an agreement
 * and settles. That is what TrustIQ does, in a few kilobytes that read the
 * page's own palette, so the field is teal on white at noon and cyan on
 * near-black at midnight without a second asset.
 *
 * The simulation is in lib/trust-field.js. What is left here is lifecycle: when
 * to run, when to stop, and what colour to be.
 */
export default function TrustField() {
  const ref = useRef(null)

  useEffect(() => {
    const canvas = ref.current
    if (!canvas) return
    const ctx = canvas.getContext('2d', { alpha: true })
    if (!ctx) return

    const still = reducedMotion()
    const modest = modestDevice()

    let field = null
    let raf = 0
    let last = 0
    let running = true
    let onScreen = true

    function palette() {
      if (!field) return
      const s = getComputedStyle(canvas)
      const a = s.getPropertyValue('--accent')
      const f = s.getPropertyValue('--text-faint')
      field.palette(
        a ? parseHex(a) : [13, 95, 102],
        f ? parseHex(f) : [124, 136, 144],
      )
    }

    function resize() {
      const box = canvas.parentElement?.getBoundingClientRect()
      if (!box || box.width < 2) return
      // Two is enough on any screen sold; three costs four times the fill for a
      // field of one-pixel lines nobody will inspect.
      const dpr = Math.min(2, window.devicePixelRatio || 1)
      canvas.width = Math.round(box.width * dpr)
      canvas.height = Math.round(box.height * dpr)
      canvas.style.width = box.width + 'px'
      canvas.style.height = box.height + 'px'
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0)

      if (field) field.resize(box.width, box.height)
      else field = createField(ctx, { width: box.width, height: box.height, modest })
      palette()
      if (still) field.settle()
    }

    function frame(now) {
      raf = 0
      if (!running || !onScreen || !field) return
      const dt = Math.min(48, now - (last || now))
      last = now
      field.step(dt)
      field.draw()
      raf = requestAnimationFrame(frame)
    }

    function start() {
      if (still || raf) return
      last = 0
      raf = requestAnimationFrame(frame)
    }

    function stop() {
      if (raf) cancelAnimationFrame(raf)
      raf = 0
    }

    resize()
    if (!still) start()

    const ro = new ResizeObserver(resize)
    if (canvas.parentElement) ro.observe(canvas.parentElement)

    // Scrolled past, and the field stops costing anything.
    const io = new IntersectionObserver(([e]) => {
      onScreen = e.isIntersecting
      if (onScreen) start()
      else stop()
    })
    io.observe(canvas)

    const onVisibility = () => {
      running = !document.hidden
      if (running) start()
      else stop()
    }
    document.addEventListener('visibilitychange', onVisibility)

    // The site follows the device's theme, so the field has to as well.
    const scheme = window.matchMedia('(prefers-color-scheme: dark)')
    const onScheme = () => {
      palette()
      if (still && field) field.draw()
    }
    scheme.addEventListener('change', onScheme)

    return () => {
      stop()
      ro.disconnect()
      io.disconnect()
      document.removeEventListener('visibilitychange', onVisibility)
      scheme.removeEventListener('change', onScheme)
    }
  }, [])

  return <canvas className="field" ref={ref} aria-hidden="true" />
}
