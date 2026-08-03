import { appendFileSync } from "node:fs"
import { createCliRenderer, TextRenderable, type MouseEvent } from "@opentui/core"

const GRID_WIDTH = 140
const GRID_HEIGHT = 84
const logPath = process.env.ALTITUDE_SPIKE_LOG
const renderer = await createCliRenderer({
  clearOnShutdown: true,
  enableMouseMovement: true,
  targetFps: 60,
})

let offsetX = 30
let offsetY = 20
let frame = 0
let dragX: number | undefined
let dragY: number | undefined
let header = "move the pointer · drag to pan · click maps a cell · q quits"

const screen = new TextRenderable(renderer, {
  id: "drag-spike",
  width: "100%",
  height: "100%",
  onMouse: handleMouse,
})
renderer.root.add(screen)

function record(fields: Record<string, unknown>): void {
  if (logPath) appendFileSync(logPath, `${JSON.stringify({ at: Date.now(), ...fields })}\n`)
}

function draw(): void {
  frame += 1
  const width = Math.max(1, renderer.width)
  const height = Math.max(1, renderer.height - 1)
  const rows = Array.from({ length: height }, (_, y) =>
    Array.from({ length: width }, (_, x) => {
      const gridX = offsetX + x
      const gridY = offsetY + y
      return gridX >= 0 && gridX < GRID_WIDTH && gridY >= 0 && gridY < GRID_HEIGHT ? "·" : " "
    }).join(""),
  )
  screen.content = `${header.slice(0, width).padEnd(width)}\n${rows.join("\n")}`
  renderer.requestRender()
}

function handleMouse(event: MouseEvent): void {
  const cellX = offsetX + event.x
  const cellY = offsetY + Math.max(0, event.y - 1)
  const deltaX = dragX === undefined ? 0 : event.x - dragX
  const deltaY = dragY === undefined ? 0 : event.y - dragY
  if (event.type === "drag") {
    offsetX = Math.max(0, Math.min(GRID_WIDTH - 1, offsetX - deltaX))
    offsetY = Math.max(0, Math.min(GRID_HEIGHT - 1, offsetY - deltaY))
    dragX = event.x
    dragY = event.y
  } else if (event.type === "down") {
    dragX = event.x
    dragY = event.y
  } else if (event.type === "up" || event.type === "drag-end" || event.type === "drop") {
    dragX = undefined
    dragY = undefined
  }
  header = `${event.type} x=${event.x} y=${event.y} cell=${cellX},${cellY} Δ=${deltaX},${deltaY} offset=${offsetX},${offsetY}`
  draw()
  record({ frame, kind: event.type, x: event.x, y: event.y, cellX, cellY, deltaX, deltaY, offsetX, offsetY })
}

renderer.keyInput.on("keypress", (key) => {
  if (key.name === "q" || key.name === "escape") renderer.destroy()
})
renderer.on("resize", draw)
draw()
