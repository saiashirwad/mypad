# MyPad

A small native iPad drawing canvas built with UIKit and PencilKit.

- Draw with Apple Pencil or your finger.
- The first tool is a ballpoint-style preset: a fine 1.2-point monoline in dark blue on warm paper. Tap that tool again to adjust its width, or choose a different ink color in the palette.
- Use the system tool palette for pens, colors, erasing, and lasso selection.
- Pinch to zoom; pan with two fingers.
- Tap **Finger: On** to switch to **Pencil Only**, where one finger pans.
- Undo and redo from the top left. The top-right arrows reset zoom and position.
- Strokes save automatically on this iPad and reopen on the next launch.

The workspace is 3,000 × 3,000 points. This first version has one canvas; it has no cloud service or account.

The ballpoint preset uses PencilKit's native monoline renderer. It keeps the nib width steady instead of using brush-like pressure variation; it doesn't simulate ink grain, skipping, or paper friction. The paper stays light in Dark Mode. On iPadOS 18 and later the ballpoint has its own palette item; the app opens with this preset selected.

## Run on the connected iPad

Open `MyPad.xcodeproj` in Xcode and run the `MyPad` scheme, or:

```sh
./scripts/run-ipad.sh
```

To use another paired iPad:

```sh
./scripts/run-ipad.sh YOUR_IPAD_UDID
```

Requires Xcode with the iOS SDK, an Apple development account in Xcode, and an unlocked, paired iPad with Developer Mode enabled. Signing currently uses the development team already configured on this Mac; change the team in Xcode's Signing & Capabilities if needed.

## Source

- `MyPad/AppDelegate.swift`: app entry point.
- `MyPad/CanvasViewController.swift`: canvas, tools, navigation, and save scheduling.
- `MyPad/DrawingStore.swift`: local loading and ordered atomic writes.

The drawing lives in the app's Application Support directory as `Canvas.drawing`. Reinstalling over the existing app preserves it; deleting the app removes its local data.

## Agent canvas prototype

The `prototype/agent-canvas` branch adds a USB file bridge: a laptop agent places PNGs or box-and-arrow diagrams beneath the ink; **Send to Agent** exports the visible canvas for retrieval. Start with `python3 scripts/canvas-bridge.py demo`. See [prototype/README.md](prototype/README.md) for the round-trip workflow, protocol, and limits.
