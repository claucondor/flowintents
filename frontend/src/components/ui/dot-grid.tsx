"use client"
import { useEffect, useRef } from "react"

export function DotGrid() {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const mouseRef = useRef({ x: -1000, y: -1000 })

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const ctx = canvas.getContext("2d")
    if (!ctx) return

    const SPACING = 32
    const DOT_BASE = 1
    const DOT_MAX = 3
    const RADIUS = 120

    let raf: number
    let cols: number, rows: number

    function resize() {
      canvas!.width = canvas!.offsetWidth
      canvas!.height = canvas!.offsetHeight
      cols = Math.ceil(canvas!.width / SPACING)
      rows = Math.ceil(canvas!.height / SPACING)
    }

    function draw() {
      if (!ctx || !canvas) return
      ctx.clearRect(0, 0, canvas.width, canvas.height)

      for (let r = 0; r < rows; r++) {
        for (let c = 0; c < cols; c++) {
          const x = c * SPACING + SPACING / 2
          const y = r * SPACING + SPACING / 2
          const dist = Math.hypot(x - mouseRef.current.x, y - mouseRef.current.y)
          const influence = Math.max(0, 1 - dist / RADIUS)
          const size = DOT_BASE + (DOT_MAX - DOT_BASE) * influence
          const alpha = 0.15 + 0.6 * influence

          ctx.beginPath()
          ctx.arc(x, y, size, 0, Math.PI * 2)
          ctx.fillStyle = influence > 0.1
            ? `rgba(0, 71, 255, ${alpha})`
            : `rgba(153, 153, 160, 0.12)`
          ctx.fill()
        }
      }
      raf = requestAnimationFrame(draw)
    }

    const handleMouseMove = (e: MouseEvent) => {
      const rect = canvas!.getBoundingClientRect()
      mouseRef.current = { x: e.clientX - rect.left, y: e.clientY - rect.top }
    }

    resize()
    window.addEventListener("resize", resize)
    canvas.addEventListener("mousemove", handleMouseMove)
    draw()

    return () => {
      cancelAnimationFrame(raf)
      window.removeEventListener("resize", resize)
      canvas.removeEventListener("mousemove", handleMouseMove)
    }
  }, [])

  return (
    <canvas
      ref={canvasRef}
      className="absolute inset-0 w-full h-full pointer-events-auto"
      style={{ opacity: 0.8 }}
    />
  )
}
