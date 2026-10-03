# Prototype verdict

Question: can a laptop agent place content on this iPad canvas, receive the user's handwritten response, and continue the interaction over USB?

**Yes. The USB round trip was exercised on the paired physical iPad on 2026-10-04.**

Observed evidence:

- Xcode built and signed the updated app; `devicectl` installed and launched it.
- The bridge accepted a box-and-arrow JSON diagram and returned an acknowledgement. The actual device screen showed that diagram beneath the drawing layer.
- The user drew new handwriting over the diagram, including “hello,” “nice,” and a circular mark.
- A Send to Agent export was retrieved with the pull command and viewed on the laptop. The exported PNG contained both the diagram and handwriting, with no app chrome.
- The first offscreen export used the system's dark-mode traits and inverted some ink colors. Explicit light traits fixed this; subsequent exports showed the older black ink and newer dark blue ink correctly.
- A clean PNG reference was imported as a second card, acknowledged, and verified through a new exported image.
- Agent-requested capture returned its own immutable snapshot metadata, PNG, and original PencilKit drawing. Metadata included canvas viewport and output pixel dimensions.
- The original ink and first agent card reopened after reinstalling the app during development.
- An out-of-bounds placement returned an error acknowledgement and did not add a card.
- Device details reported a connected **wired** transport during transfer. This establishes USB operation; it does not establish Wi-Fi operation.

The experiment supports keeping three concerns separate: native board interaction, placement/export messages, and the transport adapter. It does not justify building an MCP server or live collaboration engine yet. The next useful product experiment is using a diagram or website screenshot from real work, annotating it, and having the agent produce a revision.

Known limits: one fixed-size board; additive flattened image cards; no card movement, deletion, or insertion undo; no live stroke streaming; no automatic agent notification. The user intentionally sends a viewport snapshot, and the agent explicitly retrieves it. USB operation still depends on Xcode device services and Developer Mode. Wi-Fi is a candidate using the same paired-device transport, pending an unplugged physical test.

Local verification artifacts live in the ignored `prototype/.local/` folder. The prototype source and this verdict are captured on the local `prototype/agent-canvas` branch. The preceding drawing app remains on `main`.
