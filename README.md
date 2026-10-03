# MyPad

A minimal native iPad canvas for working with coding agents. Ask an agent to put a wireframe or diagram on the iPad, annotate it with Pencil, then say “look at my iPad.” The agent captures the area you're looking at and reads your visual feedback in the existing conversation.

One working surface. Pencil draws; fingers pan and pinch to zoom. Undo/redo float at the bottom left. A small pen button at the bottom right opens the native drawing tools, which start hidden. There is no top bar or agent status text.

Ink and references save locally and reopen after relaunch. The board is 3,000 × 3,000 points. References are PNG images; diagrams are generated on the Mac. Separate `.mypad` backups retain editable ink, references, and the saved view. Restore replaces the working surface.

## Install once on the Mac

Requires Python 3, Xcode with the iOS SDK, and an unlocked, paired iPad with Developer Mode enabled. This is a personal development workflow using Xcode device services.

```sh
./scripts/run-ipad.sh YOUR_IPAD_UDID
./scripts/install-cli.sh --skills
mypad configure --device YOUR_IPAD_UDID
```

The CLI is installed to `~/.local/bin/mypad`; that directory must be on PATH. `--skills` installs a shared skill in `~/.agents/skills/mypad`, with discovery links for Codex, Claude Code, and pi. Start a new agent session if it has already loaded its skill catalog. Device configuration lives in `~/.config/mypad/config.json`; no project setup is needed.

Keep MyPad open and the iPad unlocked while using commands. USB is verified for live placement, capture, backup, clear, and restore. Paired-device Wi-Fi uses the same transport if Xcode discovers it, but has not been physically verified here.

## From any project

```sh
mypad status
mypad put /absolute/path/wireframe.png --title 'Wireframe'
mypad capture --output ./ipad-feedback
mypad backup --output ./architecture.mypad

# Use the revision returned by capture/status/backup.
mypad clear --if-revision 42
mypad restore ./architecture.mypad --if-revision 43

# Reconcile an operation if its acknowledgement timed out.
mypad status --command-id COMMAND_UUID
```

Commands return JSON. After capture, the agent must open the returned `image` path with its image-reading tool. Default captures live in `~/Library/Application Support/MyPad/exports/`; `--output` lets an agent keep them inside its workspace.

`put` fits an image in the current view by default. Optional `--x`, `--y`, `--width`, and `--height` use board points. SVG, Mermaid, and other diagram sources should be rendered to PNG first. Native box-and-arrow JSON rendering remains available through the historical `scripts/canvas-bridge.py` prototype, but PNG is the public placement format.

Backup is separate from clear. Save a backup before restoring a different board. New handwriting changes the board revision: clear/restore reject an old revision instead of discarding newer work. Commands expire if the app does not consume them promptly. A timeout is an unknown outcome; inspect its receipt before issuing another destructive request.

## Validation and implementation

```sh
python3 -m unittest discover -s tests -v
./scripts/test-native.sh
```

The native tests run the actual PencilKit board store and bridge through Mac Catalyst libraries on the Mac; they do not replace physical iPad interaction checks.

- [Validation evidence](docs/v1-validation.md)
- [Design and command contract](docs/mypad-v1-spec.md)
- [Wayfinder map](https://github.com/saiashirwad/mypad/issues/1)
- [Terms](GLOSSARY.md)

The app has been built, installed, and launched on the connected iPad. Fresh capture and full editable backup work from an unrelated directory. The physical put/capture/backup/clear/restore loop passed, with native stroke content, references, framing, and full-board preview preserved. Claude Code and pi discovery/image-reading workflows still need their own end-to-end check.
