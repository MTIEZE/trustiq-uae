/**
 * One motion language for the whole site.
 *
 * The temptation with a brief like "make it feel alive" is a different effect
 * per section: one thing slides, the next fades, the next scales. That reads as
 * a demo of effects rather than as a product. Everything here shares one
 * easing, one distance and one duration, so the page has a single hand.
 *
 * Everything also has an off switch, and the off switch is the default on a
 * device that asked for it. Nothing below is load-bearing: with JavaScript
 * disabled or reduced motion set, every element is simply already in place.
 */

import { useEffect, useRef } from 'react'

/**
 * Marks the document as scripted, before anything renders.
 *
 * Every hidden-until-revealed rule in motion.css is written under `.js`. A
 * browser that never runs this module therefore gets the page in full rather
 * than a column of invisible sections, which is the usual way a reveal-on-
 * scroll site fails. Safe as a module side effect: the served HTML body is an
 * empty root element, so there is nothing on screen to flash.
 */
if (typeof document !== 'undefined') document.documentElement.classList.add('js')

/** The one curve. Fast out of the gate, long settle: expensive rather than bouncy. */
export const EASE = 'cubic-bezier(.22,.72,.16,1)'

const media = (q) => typeof window !== 'undefined' && window.matchMedia(q).matches

export const reducedMotion = () => media('(prefers-reduced-motion: reduce)')

/** A pointer that can hover and aim. Tilt and cursor light are meaningless without one. */
export const finePointer = () => media('(hover: hover) and (pointer: fine)')

/**
 * A rough read on whether this device should be asked to animate a canvas.
 *
 * Both of these are hints and neither is universally supported, which is why
 * the fallback is "yes, but less" rather than a blank panel: the field below
 * halves its node count here instead of switching itself off.
 */
export function modestDevice() {
  if (typeof navigator === 'undefined') return true
  const cores = navigator.hardwareConcurrency
  const ram = navigator.deviceMemory
  return (cores !== undefined && cores <= 4) || (ram !== undefined && ram <= 4)
}

/**
 * Reveal on scroll, for every `[data-reveal]` on the page.
 *
 * One observer for the document rather than one per component: a page with
 * sixty revealed elements would otherwise carry sixty observers.
 *
 * The stagger is read from the DOM at observe time. Writing `--i` by hand into
 * the JSX means renumbering a list every time somebody inserts a row, and the
 * numbering is exactly the sort of thing that then silently stops matching.
 */
export function useReveal() {
  useEffect(() => {
    const nodes = Array.from(document.querySelectorAll('[data-reveal]'))
    if (!nodes.length) return

    if (reducedMotion()) {
      // Not "animate faster". Already arrived, no transition to run.
      for (const el of nodes) el.classList.add('is-in')
      return
    }

    for (const el of nodes) {
      const group = Array.from(el.parentElement?.children ?? [])
        .filter((n) => n.hasAttribute?.('data-reveal'))
      const i = Math.max(0, group.indexOf(el))
      // Capped: an eight-card grid should not take a second to finish arriving.
      el.style.transitionDelay = `${Math.min(i, 6) * 60}ms`
    }

    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) {
          if (!e.isIntersecting) continue
          e.target.classList.add('is-in')
          io.unobserve(e.target) // Arrives once. It is not a carousel.
        }
      },
      // Fires a little before the element's top edge, so the motion is finishing
      // as it reaches comfortable reading height rather than starting there.
      { rootMargin: '0px 0px -12% 0px', threshold: 0.01 },
    )
    for (const el of nodes) io.observe(el)
    return () => io.disconnect()
  }, [])
}

/**
 * Pointer tilt, as two custom properties on the element.
 *
 * The element decides what to do with them, which keeps the maths here and the
 * art direction in the stylesheet. Values are -1 to 1 from the centre.
 */
export function useTilt(strength = 1) {
  const ref = useRef(null)

  useEffect(() => {
    const el = ref.current
    if (!el || !finePointer() || reducedMotion()) return

    let frame = 0
    let px = 0
    let py = 0

    const apply = () => {
      frame = 0
      el.style.setProperty('--tx', px.toFixed(3))
      el.style.setProperty('--ty', py.toFixed(3))
    }

    const move = (e) => {
      const r = el.getBoundingClientRect()
      px = ((e.clientX - r.left) / r.width - 0.5) * 2 * strength
      py = ((e.clientY - r.top) / r.height - 0.5) * 2 * strength
      // One write per frame. A pointermove handler that touches style directly
      // fires far more often than the screen refreshes.
      if (!frame) frame = requestAnimationFrame(apply)
    }

    const leave = () => {
      px = 0
      py = 0
      if (!frame) frame = requestAnimationFrame(apply)
    }

    el.addEventListener('pointermove', move)
    el.addEventListener('pointerleave', leave)
    return () => {
      el.removeEventListener('pointermove', move)
      el.removeEventListener('pointerleave', leave)
      if (frame) cancelAnimationFrame(frame)
    }
  }, [strength])

  return ref
}

/**
 * How far the element has travelled through the viewport, as `--p` from 0 to 1.
 *
 * Written on the element and not on :root. A custom property on the root
 * invalidates style for every node in the document on every scroll frame, which
 * is the usual reason a parallax page stutters.
 */
export function useScrollProgress() {
  const ref = useRef(null)

  useEffect(() => {
    const el = ref.current
    if (!el || reducedMotion()) return

    let frame = 0
    let visible = true

    const measure = () => {
      frame = 0
      const r = el.getBoundingClientRect()
      const span = window.innerHeight + r.height
      const p = span > 0 ? (window.innerHeight - r.top) / span : 0
      el.style.setProperty('--p', Math.min(1, Math.max(0, p)).toFixed(4))
    }

    const onScroll = () => {
      if (visible && !frame) frame = requestAnimationFrame(measure)
    }

    // Off-screen sections stop costing anything at all.
    const io = new IntersectionObserver(([e]) => {
      visible = e.isIntersecting
      if (visible) onScroll()
    })
    io.observe(el)

    measure()
    window.addEventListener('scroll', onScroll, { passive: true })
    window.addEventListener('resize', onScroll, { passive: true })
    return () => {
      io.disconnect()
      window.removeEventListener('scroll', onScroll)
      window.removeEventListener('resize', onScroll)
      if (frame) cancelAnimationFrame(frame)
    }
  }, [])

  return ref
}

/**
 * The bar earns its edge once the page has moved under it.
 *
 * At the top of a hero a ruled, frosted slab cuts the composition in half for
 * no reason. Sixty pixels down it is the thing keeping the navigation legible
 * over content, and then it should look like it.
 */
export function useNavShade() {
  const ref = useRef(null)

  useEffect(() => {
    const el = ref.current
    if (!el) return
    let frame = 0
    const read = () => {
      frame = 0
      el.classList.toggle('is-shaded', window.scrollY > 12)
    }
    const onScroll = () => {
      if (!frame) frame = requestAnimationFrame(read)
    }
    read()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => {
      window.removeEventListener('scroll', onScroll)
      if (frame) cancelAnimationFrame(frame)
    }
  }, [])

  return ref
}

/**
 * Where the pointer is inside the element, in percent, as `--mx` and `--my`.
 *
 * Used for one follow light on one block. A cursor effect on every card is the
 * kind of thing that reads as a template.
 */
export function useCursorLight() {
  const ref = useRef(null)

  useEffect(() => {
    const el = ref.current
    if (!el || !finePointer() || reducedMotion()) return

    let frame = 0
    let x = 50
    let y = 50
    const apply = () => {
      frame = 0
      el.style.setProperty('--mx', x.toFixed(1) + '%')
      el.style.setProperty('--my', y.toFixed(1) + '%')
    }
    const move = (e) => {
      const r = el.getBoundingClientRect()
      x = ((e.clientX - r.left) / r.width) * 100
      y = ((e.clientY - r.top) / r.height) * 100
      if (!frame) frame = requestAnimationFrame(apply)
    }
    el.addEventListener('pointermove', move)
    return () => {
      el.removeEventListener('pointermove', move)
      if (frame) cancelAnimationFrame(frame)
    }
  }, [])

  return ref
}
