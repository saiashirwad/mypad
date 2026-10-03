---
name: mypad
description: Use the user's iPad canvas to place visual references, inspect Pencil drawings or annotations, clear the board, and back up or restore editable work. Use when asked to look at the iPad, draw something on it, or work from its visual feedback.
---

Use the globally installed `mypad` command from any repository. MyPad must be open and the iPad unlocked. Run `mypad --help` for command syntax.

## Read the iPad

Run `mypad capture --output <workspace-local-directory>`, then open the returned `image` path with your image-reading tool. Capture is the current view, so the user's pan/zoom selects the relevant context. Complete the read only after inspecting the image pixels. If capture fails, report the error and ask the user to open/unlock the app or reconnect the device; a previous image does not establish current state.

## Place a reference

Generate a PNG on the Mac and run `mypad put <absolute-png-path> --title <short-title>`. Diagram sources can remain in the project. Default placement fits the current view; explicit geometry is available. Read the acknowledgement to confirm placement.

## Start afresh

Capture first to obtain the current revision. Preserve work with `mypad backup --output <new-path>.mypad` when requested or appropriate before replacing work. Run `mypad clear --if-revision <current-revision>` only when starting afresh is intended, then place new content. Backup and clear are separate operations.

## Restore

Back up the current board before restoring another one. Use `mypad status` for its current revision, then `mypad restore <backup-path>.mypad --if-revision <revision>`. Restore replaces the whole board and recovers editable handwriting and saved framing.

On a revision conflict, capture again and account for the newer work. On an unknown-outcome timeout, use `mypad status --command-id <id-from-error>` to reconcile its receipt, then capture current state before another mutation. The command may already have applied. Report successful paths and revisions without claiming an unacknowledged operation completed.
