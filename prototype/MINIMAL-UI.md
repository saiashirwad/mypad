# Minimal canvas controls — throwaway prototype

Question: where should minimal undo/redo and hidden drawing tools live on a full-screen iPad canvas?

Open `minimal-ui.html` directly, or run `python3 -m http.server 8765 --directory prototype` and visit `/minimal-ui.html?variant=B`.

Three structurally different arrangements: A bottom cluster, B split corners, C vertical side rail. All use the same reference and sample annotations. Tools start hidden. The floating dark variant switcher and explanatory text are prototype controls outside the iPad preview, not proposed app UI.

Only palette toggling, sample-ink undo/redo, and simulated connection state are interactive. No actual Pencil drawing, persistence, transport, or app changes. No winning variant has been selected. Native hit targets, palm occlusion, real Pencil interaction, and landscape/portrait device behavior need validation later.
