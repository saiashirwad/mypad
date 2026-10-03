# Working on MyPad

MyPad is one native iPad board shared with coding agents through a global Mac CLI. Agents place PNG references; the user draws with Pencil and frames feedback by panning and zooming. Capture reads that view. Backup preserves the editable board. Keep this core small and agent-neutral.

## Read when relevant

- For setup and command examples, read [README.md](README.md) and `python3 scripts/mypad.py --help`.
- Before changing behavior, persistence, or the command protocol, read [the v1 spec](docs/mypad-v1-spec.md). Use [GLOSSARY.md](GLOSSARY.md) for domain terms.
- Before operating the user's iPad, read [the MyPad skill](skills/mypad/SKILL.md).
- For prior verification and remaining gaps, read [validation evidence](docs/v1-validation.md). Historical evidence is not verification of your changes.
- Track Wayfinder work in GitHub issues, starting from [the project map](https://github.com/saiashirwad/mypad/issues/1). Keep issue descriptions and completion evidence aligned with the delivered scope.

## Code boundaries

| File | Responsibility |
| --- | --- |
| `MyPad/CanvasViewController.swift` | Board presentation, Pencil input, pan/zoom, floating controls, viewport rendering, foreground bridge polling |
| `MyPad/DrawingStore.swift` | Editable board state, revisions, migration, serialized disk writes, durable saves |
| `MyPad/AgentBridge.swift` | File-mailbox commands, validation, receipts, reference placement, capture, backup, clear, restore |
| `scripts/mypad.py` | Standalone Python CLI, device transport, local exports, archive validation |
| `skills/mypad/SKILL.md` | Instructions for agents using the installed CLI |

The CLI uses Python's standard library and Xcode device services. The current workflow needs neither a daemon nor an MCP server. `prototype/` and `scripts/canvas-bridge.py` contain historical work; extend the public `mypad` CLI for new behavior.

## Preserve these contracts

- Keep one working surface and a minimal UI: Pencil draws, fingers navigate, tools start tucked away, undo/redo and the pen button float in the bottom corners. Additional chrome needs a concrete user need.
- References and ink share board coordinates and the same transformed container. Capture includes both and excludes controls; its default bounds are the current viewport.
- Keep UIKit, PencilKit, and live board mutation on the main thread. The store owns serialized persistence; publish the current manifest only after its referenced files exist. Preserve recoverable files when loading fails.
- Clear and restore replace the board. Require a current revision and command expiry; preserve durable command IDs and receipts so replay cannot apply a mutation twice. A timeout means an unknown outcome: reconcile the receipt before retrying.
- A `.mypad` backup contains editable ink, PNG references, the view, and a preview. A capture is not a backup. Validate the complete restore package before changing the board.
- The on-device mailbox is still `Documents/AgentBridgePrototype`. Its name is a compatibility boundary, including migration from the prototype; changing it requires an explicit migration plan.
- Register new Swift files in `MyPad.xcodeproj/project.pbxproj`. Preserve availability guards for APIs newer than the deployment target.
- Compare decoded PencilKit strokes and rendered output when checking round trips. Serialized drawing bytes can differ after decoding without losing content.

## Validate the affected boundary

For CLI/archive/receipt changes:

```sh
python3 -m unittest discover -s tests -v
```

For store or bridge changes, also run:

```sh
./scripts/test-native.sh
```

This runner exercises the actual store and bridge with Mac Catalyst PencilKit libraries. Its temporary app bundle supplies the bundle identifier PencilKit needs; retain that wrapper. It does not exercise the view controller or physical input.

For app changes, build with the iOS SDK:

```sh
xcodebuild -project MyPad.xcodeproj -scheme MyPad -sdk iphoneos \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath build-check build
```

For device acceptance, find the paired device with `xcrun devicectl list devices`, then build, install, and launch:

```sh
./scripts/run-ipad.sh DEVICE_UDID
```

The iPad must be paired, unlocked, and running MyPad for bridge commands. Save an editable backup before a destructive verification loop and restore the user's board afterward unless the user requests a different result. Test UI changes on the iPad with the relevant Pencil, finger, palette, undo/redo, and rotation interactions. A successful build or exported screenshot alone does not establish interaction behavior.

The installer copies the CLI and skill rather than running them from this checkout. After editing either, reinstall before testing the global workflow:

```sh
./scripts/install-cli.sh --skills
```

Run a command from an unrelated directory to verify project independence. USB and paired-device Wi-Fi require separate physical checks. Report build, tests, installation, device behavior, and Git delivery as distinct results, with any unverified parts stated clearly.
