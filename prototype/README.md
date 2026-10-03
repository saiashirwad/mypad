# Agent canvas bridge — prototype

Question: can a laptop agent place something on the iPad, let the user annotate it, and read the result back without an MCP server or hosted service?

This prototype uses the already-paired Xcode device connection and `devicectl` file transfer. MyPad checks a local command inbox every 0.5 seconds while the canvas is visible. It renders a JSON diagram or PNG below the PencilKit ink. Both layers share one scroll/zoom container. **Send to Agent** publishes a PNG of the visible canvas, the original PencilKit drawing, and metadata into an outbox.

This is a file mailbox, not live stroke streaming. The button prepares an export; an agent must run the pull command to receive it. It does not wake an idle agent or send a chat message.

## Use it

Keep MyPad open and the iPad unlocked. From the project folder:

```sh
# Put the example architecture diagram on the iPad.
python3 scripts/canvas-bridge.py demo

# Place a diagram described with boxes, labels, and arrows.
python3 scripts/canvas-bridge.py put prototype/examples/round-trip.json --x 140 --y 140

# Place a website screenshot or other PNG. Coordinates are canvas points.
python3 scripts/canvas-bridge.py put /absolute/path/screenshot.png --title 'Homepage' --x 1600 --y 140 --width 900 --height 1400

# After the user taps Send to Agent, retrieve that export.
python3 scripts/canvas-bridge.py pull

# Ask the app to capture the current view, then retrieve that specific export.
python3 scripts/canvas-bridge.py capture
```

The commands print JSON. The returned `image` path is ready for the agent's local image-viewing tool. Downloads default to `prototype/.local/exports/`, which is ignored by Git. Use `--output PATH` after `pull` or `capture` to change the destination. Use `--device UDID` before the subcommand, or set `MYPAD_DEVICE_ID`, for another iPad.

`put` returns only after the app acknowledges placement. If MyPad is not visible, the command stays queued and the CLI times out after 20 seconds. Open the app to consume it. Each put creates a new artifact; there is no replace, move, or delete command in this first experiment. Place a new diagram in free canvas space when iterating.

## Diagram format

See `examples/round-trip.json`. The top-level `width` and `height` define the card's size. Each node has a unique `id`, `label`, `x`, `y`, `width`, and `height`. Edges reference nodes through `from` and `to` and may have a `label`. Newlines in labels are supported. Nodes must fit inside the card, and the card must fit inside the 3,000 × 3,000 canvas.

The iPad renders a diagram to an image; its boxes are not individually editable on the iPad. The JSON on the laptop is the editable source. PNG imports use the provided frame; preserve their aspect ratio when setting both width and height.

## Files and ownership

In the app's data container:

```text
Documents/AgentBridgePrototype/
  inbox/<command UUID>.json
  assets/<image filename>.png
  board.json
  outbox/ack-<command UUID>.json
  outbox/snapshot-<snapshot UUID>.png
  outbox/snapshot-<snapshot UUID>.json
  outbox/ink-<snapshot UUID>.drawing
  outbox/latest.json
```

The laptop transfers image assets before publishing the command. The app writes the board manifest atomically, then acknowledges placement. Exports publish their image, raw ink, and immutable metadata before updating `latest.json`. `capture` retrieves its own snapshot rather than relying on the latest pointer.

The export is the current viewport, including all visible agent artifacts and handwriting, without the app toolbar or tool palette. Metadata contains the viewport in canvas coordinates, PNG pixel dimensions, all artifact IDs, timestamp, and total board stroke count. To map a point in the PNG back to the canvas:

```text
canvasX = viewportX + pixelX × viewportWidth / pixelWidth
canvasY = viewportY + pixelY × viewportHeight / pixelHeight
```

The raw drawing contains the whole board's ink. Original drawing persistence remains in Application Support/Canvas.drawing. Adding agent content does not replace it.

## Transport

USB is the initial verified transport. The protocol has no cable-specific logic: `devicectl` selects the paired device's available connection. Xcode supports paired-device Wi-Fi connections, so the same commands can be tried after unplugging the cable with both devices on the same network. Successful USB transfer is not proof that wireless discovery works on this particular network.

This depends on Xcode and a development-enabled, paired iPad. A future standalone Wi-Fi version could replace the file-transfer adapter with a local authenticated connection while keeping the placement/export messages. MCP can then be a laptop-side adapter exposing those operations.

## Boundaries

This experiment has one persistent board, additive image cards, native handwriting, and deliberate viewport exports. It has no agent chat, automatic interpretation, semantic editing, concurrent agent coordination, background processing, or undo for inserted image cards. Commands and exports accumulate locally; no automatic cleanup removes the user's content.

Validation notes are recorded in `VERDICT.md`. The prototype lives on the local `prototype/agent-canvas` branch; `main` preserves the preceding drawing app.
