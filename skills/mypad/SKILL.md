---
name: mypad
description: Read and write the user's iPad canvas - write Markdown/SVG/HTML onto it, place PNGs, inspect Pencil drawings or annotations, clear, back up or restore. Use when asked to look at the iPad, put or draw something on it, or work from its visual feedback.
---

Use the global `mypad` command from any directory. MyPad must be open and the iPad unlocked. Output is one line of JSON.

## Read

`mypad capture` → `{"ok":true,"revision":N,"image":PATH,"ids":[...],"strokes":K}`. Open `image` with your image-reading tool; a path alone is not a read. Capture shows the user's current view (their pan/zoom picks the context). Captures go to the default exports folder; don't pass `--output` into a project tree.

## Write

Pipe text straight to the iPad; it renders there. No diagram files or Mac-side rendering.

```sh
mypad write <<'MD'
## Title
- Markdown (default): lists, `code`, tables, fenced blocks
MD
mypad write --format svg <<'SVG'
<svg width="400" height="200"><rect x="10" y="10" width="160" height="60" rx="10" fill="none" stroke="#2457c5" stroke-width="3"/></svg>
SVG
```

- Returns `{"ok":true,"revision":N,"id":ID,"frame":[x,y,w,h]}` (board points). Keep `id`.
- Everything renders straight onto the board as plain text/drawing, no box. `--width` (default 640 points) is the wrap width.
- Placement: centered in the user's current view, moved down past any ink or item it would cover; `--below ID` / `--right-of ID` to stack pieces; `--x X --y Y` for exact.
- Change something in place, keeping the user's ink: `mypad write --replace ID` (or `mypad put file.png --replace ID`). Delete one item: `mypad remove ID`.
- Prefer several small writes over one huge one. Use `mypad put /abs/file.png` only for an existing image.

## Start afresh

`mypad clear --backup <new-path>.mypad` backs up and clears in one step. Only clear when starting afresh is intended.

## Restore

Back up first, then `mypad restore <backup>.mypad --if-revision <revision from your latest command>`. Restore replaces the whole board.

On `revision_conflict` the user drew something since; capture again and account for it. On `unknown_outcome`, run `mypad status --command-id <id-from-error>`; the command may already have applied.
