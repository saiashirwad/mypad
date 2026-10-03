# MyPad v1: a Pencil canvas for coding agents

Status: initial implementation on `feature/mypad-v1`. See `v1-validation.md` for verified behavior and remaining physical interaction checks.

Canonical planning map: [Make the iPad a daily canvas for coding agents](https://github.com/saiashirwad/mypad/issues/1).

## Experience

The iPad sits beside the Mac. From any repository, the user asks a coding agent to put a wireframe, diagram, or other visual reference on the iPad. They annotate it with Pencil, or draw from scratch on a blank board. Saying “look at my iPad” lets the agent capture and inspect the current view inside the existing conversation. The agent can back up the board, clear it, and place a new reference.

One board. No project switching, accounts, chat UI, automatic agent wake-up, or diagram-node editor. No MCP in v1. Reference movement, semantic instruction cleanup, and live stroke streaming are deferred.

The existing 3,000 × 3,000-point workspace is sufficient for v1. Pan/zoom frames what the agent sees. Multiple images may exist on this one surface, but there is no board library. Clear removes all references and ink, resets the view, and commits an empty board. Backup is a separate primitive.

## iPad interface

Use the selected [B — split corners prototype](https://github.com/saiashirwad/mypad/blob/153139c/prototype/minimal-ui.html):

- Canvas fills the app window. No navigation bar, app title, persistent status text, Send button, input toggle, or prototype switcher. Hide the app's status bar for this drawing surface.
- Pencil always draws. One-finger drag pans; pinch zooms. Fingers can operate controls but never make ink.
- Bottom-left floating capsule contains undo and redo. Disabled actions are subdued. Keep each action's hit target at least 44 points while making the visible glyph small.
- Bottom-right floating pen button toggles the drawing palette. Palette is hidden on launch, dismissible by its button or a tap outside its controls; retain the selected tool when it closes. A canvas tap used to dismiss tools must not generate ink or unexpectedly move the view.
- Reuse the current PencilKit tool picker first, exposing pens, colors, erasing, and lasso through the floating button. Do not build a custom tool system to reproduce the HTML mockup. Position the picker using available native APIs; verify that it does not permanently cover the corner controls.
- Retain the existing fine monoline writing preset and light paper. Safe-area-aware placement in portrait, landscape, and window resizing. No dark-mode ink inversion in capture.
- Undo/redo covers native ink edits in v1. Clear and restore reset the ink undo history so old strokes cannot reappear against a different board. Reference insertion undo is deferred.

Do not show a green connectivity dot based merely on “the app opened” or an old acknowledgement. The current file bridge has no continuous link-health signal. Omit the dot from the first acceptance baseline; `mypad status` provides on-demand connection checking; `status --command-id <id>` reconciles a timed-out operation. A tiny indicator can follow a genuinely measured health protocol later without adding text to the canvas.

## Three representations

1. **Reference:** PNG, with its original pixels retained and a frame in board coordinates. Agents either upload a PNG or send Markdown, HTML or SVG text that the iPad renders once with WebKit (`WriteRenderer`, bundled `marked.min.js`) into a PNG reference, so no Mac-side renderer is needed. Rendered references are static images; there is no live web content, Excalidraw or tldraw runtime.
2. **Capture:** a fresh composite PNG of the current view plus metadata. It contains references and ink, excluding tool UI and system chrome. The agent must open the returned image using its image-reading tool.
3. **Backup:** a versioned, self-contained ZIP archive with extension `.mypad`. It restores the full board with native editable ink. A preview is for browsing, not the source used to restore.

Keep compatibility with the prototype's JSON box-and-arrow renderer only if it is essentially free; it is not part of the minimum public v1 command contract. PNG is the required placement format.

## Backup package v1

```text
example.mypad
  manifest.json
  ink.drawing
  assets/<reference-id>.png
  preview.png
```

Example manifest:

```json
{
  "format": "mypad-board",
  "version": 1,
  "createdAt": "2026-10-04T10:00:00Z",
  "revision": 42,
  "boardSize": {"width": 3000, "height": 3000},
  "view": {"centerX": 1500, "centerY": 1500, "zoomScale": 1},
  "inkFile": "ink.drawing",
  "previewFile": "preview.png",
  "references": [
    {
      "id": "a-unique-reference-id",
      "title": "Wireframe",
      "file": "assets/a-unique-reference-id.png",
      "frame": {"x": 140, "y": 140, "width": 1000, "height": 700}
    }
  ]
}
```

Reference order is draw order. All coordinates are board points; PNG pixel size is independent. Save view center and zoom, then clamp to the receiving window's valid geometry on restore. Exact viewport extent may differ on a different window size.

The iPad serializes the ink and manifest from one board state and stages all immutable assets before publishing backup completion. Include the full board preview, scaled to a bounded image size; preview quality never affects restore fidelity. The Mac downloads the staged files, verifies required entries, and publishes the final archive atomically. Report success only after the archive exists on the Mac. Backup does not change the board.

Restore validates format/version, paths, image data, finite geometry, bounds, asset presence, and native ink decoding before changing the board. Reject unsupported versions and incomplete packages. The ZIP extractor accepts only declared package paths, rejects traversal and symlink entries, and bounds archive/file sizes to avoid exhausting memory or disk. Initial supported limits: 64 references, 20 megapixels per decoded image, 100 MiB per input PNG, 100 MiB ink data, and 512 MiB total uncompressed archive; report explicit limit errors.

Stage restore in a new local board generation and atomically switch the active manifest only when complete. Retain the prior committed generation until the new generation is committed and live UI adoption succeeds. Startup should recover either the old or new complete board, never a mixture. Migration copies the existing `Canvas.drawing` and `board.json` references into the first coherent generation; preserve originals until a successful migration.

Native PencilKit ink is intended for restoration in MyPad. The preview/capture is the portable representation other image viewers and agents can read. Do not promise that arbitrary diagram editors can edit a `.mypad` backup.

## Global CLI

Use a small Python-stdlib CLI wrapping the existing `devicectl` file mailbox. No Mac daemon is required for this transport.

```sh
mypad configure --device <paired-device-id>
mypad status
mypad put /absolute/path/wireframe.png --title 'Wireframe'
mypad capture --output ./ipad-feedback
mypad backup --output ./architecture.mypad
mypad clear --if-revision <revision-from-capture>
mypad restore ./architecture.mypad --if-revision <current-revision>
```

| Operation | Contract |
| --- | --- |
| `configure` | Save the selected device once in user-level config; no repository changes. |
| `status` | Request a fresh app acknowledgement; distinguish transport reachable from app responsive. |
| `put` | Validate and place a PNG (or swap one with `--replace`), acknowledge after durable insertion, and return reference ID, frame, and board revision. |
| `write` | Render Markdown/HTML/SVG on the iPad into a PNG reference (or re-render one with `--replace`); same acknowledgement as `put`. Protocol version 2. |
| `remove` | Delete one reference; ink is untouched. Protocol version 2. |
| `capture` | Capture current view now; return this command's image, metadata, and board revision. Never fall back to the previous capture. |
| `backup` | Save the full current board to the requested Mac `.mypad` path; return path and captured revision. |
| `clear` | Empty the board and reset framing. Requires a matching current board revision; backup remains separate. |
| `restore` | Replace the board from a validated backup, with a matching current revision. Return the new revision. |

`put` supports optional `--x`, `--y`, `--width`, `--height`. Preserve aspect ratio when computing omitted dimensions. With no geometry, fit and center the reference in the current view with margin; cap magnification/size to board bounds. Adding it focuses the image after the user finishes any active Pencil gesture. No unattended mutation should interrupt an in-progress stroke.

Machine-readable JSON on stdout, diagnostic text on stderr, nonzero exit on failure. Required success fields: `ok`, `operation`, `commandId`, `revision`, plus operation-specific paths/geometry. Error codes distinguish config missing, device unavailable, app unresponsive, invalid input, revision conflict, and timeout/unknown outcome. Paths are absolute.

Revision is a durable monotonically advancing board-content counter, including ink edits and reference changes. View movement does not change content revision. A restored backup receives a new current revision rather than reusing a historical revision. Clear/restore reject stale revisions to protect handwriting added after an agent read. This protects against stale destructive requests; it is not a multi-agent coordination system.

Install the executable into `~/.local/bin/mypad` and its supporting files into `~/.local/share/mypad`. Store device config beneath `~/.config/mypad`. Default capture exports live beneath `~/Library/Application Support/MyPad/exports/<capture-id>/`; `--output` lets an agent keep files inside its permitted workspace. Do not require this repository as cwd or hard-code the current device ID. Do not overwrite existing output archives by default.

## Command delivery and persistence

Keep the native board, durable storage, and transport adapter as separate responsibilities. Pencil stroke rendering and pan/zoom remain on the UIKit fast path. Only settled durable state and explicit commands cross into persistence/bridge work.

Commands have unique IDs, protocol version, operation, and an expiry. Mac sends assets first, then the final command file. App accepts only complete valid commands, serializes board mutations, and checks expiry/revision immediately before applying destructive operations. Persist operation receipts so retries of a command ID return the same outcome rather than applying twice. Invalid complete commands receive an error receipt; incomplete transfers must not block valid commands indefinitely.

Acknowledgement means the requested state is durably committed or the requested export is complete. A Mac timeout can mean an unknown outcome; never claim a queued operation was canceled. Reconcile the original command ID before offering a retry. Expired commands cannot execute on a later app reopen. Preserve the existing UUID-correlated capture behavior.

Clear/restore are serialized with ink changes and treated as short board transitions. Validate/stage asynchronously, then check the content revision again and commit without allowing an intervening Pencil edit to be lost. Autosave and bridge snapshots use one coherent board store, replacing the current independent ink and reference persistence paths.

## Setup and agent instructions

One-time setup: build/install the native app, pair the iPad with Xcode, configure the device ID, install the global CLI, and install user-level instructions/skill for each agent. Existing Apple development signing and Developer Mode remain requirements. MyPad must be foreground and the iPad unlocked for this first transport.

The agent instructions explain:

- Run `mypad capture` when asked to look at the iPad, then open the returned PNG in the ongoing conversation. A file path alone does not put pixels into model context.
- Send text with `write`; use `put` for existing PNGs. Start afresh through explicit `clear`; do not infer a clear from a placement request.
- Use `backup` when preserving work, and before restoring a different board. Retain the archive path in the conversation.
- Use the latest returned revision for clear/restore. On conflict, capture again and explain the newer work rather than clearing blindly.
- If the app/device is unavailable, report the error with a short action the user can take. Never use an old export as “what is on the iPad now.”

Actual Codex, Claude Code, and pi clients must each run the command and inspect the image without a session restart or manual upload. Install the skill/instructions according to each client's real user-level conventions; do not assume a single skill directory is discovered by all three.

## Connection

USB is the acceptance baseline. Research supports testing the same `devicectl` adapter over paired-device Wi-Fi; wireless is not yet established on this network. Record the actual connection mode during an unplugged put/capture round trip. If it fails, ship the usable wired version rather than introducing a network service into this scope.

No continuous connectivity dot or background agent notification is promised by a command mailbox. A standalone local network connection can be a later transport adapter if everyday measurements justify it.

## Implementation sequence

1. Coherent board store and migration preserving existing drawings/reference assets; package backup/restore contract.
2. Minimal native UI, Pencil-only behavior, hidden palette, and safe-area-aware corner controls.
3. Protocol operations and globally installable CLI with receipts, revision guards, expiry, and explicit error results.
4. User-level agent instructions and each client's real image-reading workflow.
5. Physical-iPad daily-loop verification, wired first; paired Wi-Fi test as a bounded follow-up.

This is an implementation sequence, not additional decision tickets.

## Acceptance checks

- Existing drawing/reference content survives migration and app relaunch. A migration/read failure preserves original files and does not overwrite them with an empty board.
- On the physical iPad: Pencil writes smoothly, fingers only navigate, palette starts hidden and toggles, undo/redo works, and no bar/status prose remains. Check portrait and landscape, safe areas, and hand occlusion.
- From an unrelated repository, each supported agent places a PNG and inspects a fresh viewport capture showing both reference and actual handwriting. The user can draw on an empty board too.
- Pan/zoom changes the capture region. Metadata maps PNG pixels back to board coordinates; no controls appear in the image and ink colors match the light paper.
- Back up multiple references and handwriting, clear, restore, erase an individual restored stroke, and compare full state and framing. Preview image alone must not be used to restore ink.
- Corrupt/unsupported/incomplete backups fail without changing the board. Interruption during save/restore reopens a complete committed board.
- New ink after capture causes stale clear/restore to fail. Repeated command delivery does not duplicate insertions. Timed-out/expired destructive commands do not unexpectedly run later.
- Offline device and backgrounded app yield actionable errors, not stale captures. Verify USB physically; claim Wi-Fi only after an unplugged successful test.

Use meaningful storage/protocol tests for transaction and replay failures, plus actual native interaction and physical Pencil checks. The HTML prototype establishes a layout choice, not native acceptance.

## Source pointers

- [Product decision map](https://github.com/saiashirwad/mypad/issues/1) and its resolution comments.
- [Prior-art research](https://github.com/saiashirwad/mypad/blob/research/ipad-prior-art/research/prior-art.md).
- [Connection and agent-interface research](https://github.com/saiashirwad/mypad/blob/bf91ec1/research/connection-interface.md).
- Existing source: `MyPad/CanvasViewController.swift`, `MyPad/AgentBridge.swift`, `MyPad/DrawingStore.swift`, `scripts/canvas-bridge.py`.
- Existing physical-device evidence: `prototype/VERDICT.md`; not rerun during this planning effort.
