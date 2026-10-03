# MyPad v1 validation

Initial implementation checked on 2026-10-04, branch `feature/mypad-v1`.

## Passed

- iOS device build without signing, then signed build/install/launch on the connected physical iPad.
- Global CLI installation and one-time configuration. `mypad status`, fresh `capture`, and full-board `backup` succeeded from `/tmp`, outside the repository.
- Captured PNG opened in this Codex conversation and showed the actual handwriting, with matching light-paper ink colors. Capture returned its command-specific image, viewport, and revision.
- Backup archive contains 277 real PencilKit strokes and two reference images, their positions, saved view, and a full-board preview. A copy is preserved at `~/Library/Application Support/MyPad/backups/pre-v1-verification-2026-10-04.mypad` on this Mac.
- Ten Python tests: package round trip, traversal rejection, unknown version, missing asset, duplicate identity, undeclared asset, nonfinite geometry, oversized image, symlink rejection, and unrelated command receipt rejection.
- Eleven native checks using the actual Swift/PencilKit store and bridge through Mac Catalyst libraries: migration preserving legacy files; fresh capture identity; real editable backup; stale and expired destructive requests; coherent clear after queued autosave; mutation replay after lost receipt; restore/relaunch; invalid native ink preserving current work; default image placement and replay; invalid image paths; incomplete inbox files not blocking valid commands.
- Existing drawings were migrated rather than replaced. Initially skipped physical clear/restore when revision 28 had advanced to 80. After the user explicitly authorized clearing and changing content during development, backed up the newer board and verified a full physical clear → put → capture → restore → backup loop.
- Physical restore retained all 332 native strokes with identical control-point properties, reference entries, saved view, and byte-identical full-board preview. Serialized PencilKit data changed in representation; equality was checked against decoded stroke content, not raw serialization. The newer backup is preserved at `~/Library/Application Support/MyPad/backups/before-roundtrip-2026-10-04.mypad`.
- Actual native UI rendered in a separate scratch Mac Catalyst app using the same controller: split-corner controls, empty canvas, tools hidden. This is a layout check; the Mac preview does not show the iPad tool palette.

## Still to check interactively

- Physical palette opening/dismissal, corner control ergonomics, ink undo/redo, finger-only navigation, rotation, and hand occlusion. The native code builds and the app is running, but an exported canvas image excludes controls and cannot verify their layout.
- Paired Wi-Fi with USB unplugged.
- Claude Code and pi opening a returned image in their ongoing conversations. Their skill discovery links are installed; no sessions were launched for this check.

No claim of full physical UI acceptance or wireless support is made by the build or storage tests.
