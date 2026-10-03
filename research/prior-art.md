# Visual reference and Pencil feedback prior art

Research for [Learn from existing visual annotation and agent canvas workflows](https://github.com/saiashirwad/mypad/issues/2), under [Design the smallest daily iPad and coding-agent loop](https://github.com/saiashirwad/mypad/issues/1). Checked 2026-10-04 against primary documentation. This is desk research: no product, iPad, network, or agent-client interaction was tested.

## Answer

Existing products demonstrate both halves of the desired interaction: native iPad reference annotation, and agent manipulation of a visual canvas. The sources inspected do not demonstrate the exact complete loop of a local Mac agent, a dedicated Pencil-first iPad canvas, and on-demand retrieval from any repository. That is a bounded finding about these sources, not a claim that no such product exists.

The best fit for the first version is a replaceable visual reference with a separate editable ink layer, plus an explicit snapshot request from the agent. Diagram layout and revisions can remain on the agent side. Selectively removing ink is mechanically feasible; deciding which marks represent resolved instructions is a separate interpretation problem.

## Relevant examples

| Prior art | Documented behavior | Useful pattern for mypad | Boundary |
| --- | --- | --- | --- |
| Apple Freeform | Combines files, shapes, handwriting, and images; Pencil drawing and zoom; iCloud boards update across devices signed into the same Apple Account. | A reference and handwriting can share a spatial canvas. | The cited guide documents user collaboration and Apple-account sync, not a local coding-agent API. |
| Concepts | Imports images to scale, allows positioning/resizing, and puts images in a bottom layer when automatic layers are enabled. Export can retain original import size when markup stays inside its boundaries. | Keep reference content separate from ink; preserve size and coordinates across export. | The documented workflow uses import/export UI, clipboard, and drag-and-drop. It does not establish automatic agent retrieval. |
| Excalidraw | Stores editable scene JSON separately from PNG/SVG rendering; exports can embed scene data in PNG/SVG. | Retain editable source independently of the image an agent reads. | An image of a diagram and its structured scene are different representations. Supporting scene editing on iPad would expand scope beyond the user's first-version requirement. |
| Excalidraw MCP App | Official repository documents streamed diagrams, camera control, and fullscreen editing in MCP Apps clients. Local stdio installation is available. Releases document checkpoint/restore and element deletion. | Small mutation tools and recoverable states are useful models for agent revisions. | MCP Apps support is a client capability; this is a chat-embedded editor, not documented transport to a separate native iPad. |
| tldraw MCP App | Creates, edits, and deletes shapes; passes canvas state back into chat context. | Explicit visual state feedback lets an agent respond to user edits. | The launch article describes a canvas inside chat and initially Cursor support. Planned client support is not proof of today's support or of CLI-agent/iPad integration. |

Sources for each row: [Freeform guide](https://support.apple.com/en-ie/guide/ipad/ipad9c59637d/ipados), [Concepts import](https://concepts.app/en/manual/import), [Concepts export guidance](https://concepts.app/en/tutorials/tips-exporting-your-designs/), [Excalidraw JSON schema](https://docs.excalidraw.com/docs/codebase/json-schema/), [Excalidraw export API](https://docs.excalidraw.com/docs/@excalidraw/excalidraw/api/utils/export), [Excalidraw MCP repository](https://github.com/excalidraw/excalidraw-mcp), [Excalidraw MCP releases](https://github.com/excalidraw/excalidraw-mcp/releases), [tldraw MCP launch article](https://tldraw.dev/blog/tldraw-mcp-app).

These are patterns to borrow, not recommendations to install those products. None is evidence that mypad needs an infinite canvas, collaborative editing, an account service, or an embedded chat UI.

## Native framework option worth checking

Apple's PaperKit combines PencilKit drawing with markup such as shapes and images and handles rendering and saving/loading markup. That may reduce custom work if moving references becomes important. Its existence does not justify rewriting the working prototype: adoption needs an SDK/deployment-target check and a concrete comparison with the current separate-reference/PencilKit implementation. [Meet PaperKit, WWDC25](https://developer.apple.com/videos/play/wwdc2025/285/).

Apple also documents richer writable element access in newer PaperKit APIs, explicitly associated with OS 27. Treat that as availability-dependent, not an assumed capability of this project's installed SDK or the user's iPad. [Unwrap PaperKit, WWDC26](https://developer.apple.com/videos/play/wwdc2026/372/).

## Selective ink removal: geometry versus meaning

PencilKit exposes a drawing's strokes and lets an app construct a new drawing from a sequence of strokes. Therefore whole-stroke removal can be implemented by retaining the desired subset and assigning the resulting drawing to the canvas. This is an inference from the documented API, not a tested implementation here. [PKDrawing.strokes](https://developer.apple.com/documentation/pencilkit/pkdrawing-swift.struct/strokes), [PKDrawing.init(strokes:)](https://developer.apple.com/documentation/pencilkit/pkdrawing-swift.struct/init(strokes:)).

Each stroke has rendered bounds, including width and transform, which can provide a coarse candidate set for region selection. Bounds intersection alone does not prove the visible line intersects the chosen region. The stroke path is a B-spline, and its control points should not be mistaken for points lying on the rendered line. Existing masks and masked path ranges matter when interpreting erased strokes. [PKStroke.renderBounds](https://developer.apple.com/documentation/pencilkit/pkstroke/3595092-renderbounds), [Inspect, modify, and construct PencilKit drawings, WWDC20](https://developer.apple.com/videos/play/wwdc2020/10148/).

Partial erasure is represented by a stroke mask. A manually constructed mask is possible, but preserving earlier erasure and accounting for stroke transforms makes region clipping more involved than whole-stroke filtering. [PKStroke.mask](https://developer.apple.com/documentation/pencilkit/pkstroke-swift.struct/mask-8g6sx).

Apple's newer PencilKit session documents stable stroke UUIDs, selection access, programmatic erasing, and substroke extraction for OS 27. The source explicitly places these APIs in that version. Verify project SDK and device support before relying on them; they are not necessary to establish basic whole-stroke filtering. [Read between the strokes with PencilKit, WWDC26](https://developer.apple.com/videos/play/wwdc2026/203/).

The unresolved part is semantic identification. A handwritten arrow can mean "move this box," a diagram connection, or an annotation about another annotation. Nothing in the geometry APIs establishes which meaning the user intended. Neither handwriting recognition nor stroke deletion alone answers "which marks are now resolved?"

Proposed first-version contract, requiring a later human decision:

1. Reading the iPad produces one composite image and a revision identifier while retaining the reference and native ink separately.
2. Replacing the reference preserves ink by default; clearing ink is an explicit operation.
3. If selective cleanup is included, make it refer to an explicit region or snapshot-scoped stroke selection, with an undoable revision. Whole-stroke deletion is easier to reason about than automatic partial erasure.
4. A request based on an older snapshot must not silently delete marks added after that snapshot. Revision checking is an application responsibility.

These are design inferences, not settled decisions or implemented behavior. A small experiment should use crossing arrows, handwritten words with multiple strokes, and new ink added after snapshot retrieval to judge whether region deletion is adequate. If those cases are frustrating, keep selective cleanup outside the first daily version rather than promising semantic erasure.

## What this research resolves and leaves open

The prior art supports a small, layered annotation loop without building an editable diagram editor. Agent-facing diagram tools and human-facing Pencil tools need not share a representation. Preserving both source data and a readable image is a useful pattern. Ordinary export, MCP Apps interaction, and native iPad transport are distinct capabilities.

This research does not choose Wi-Fi versus USB, CLI versus MCP, canvas dimensions, multiple-board behavior, reference movement, or ink cleanup semantics. Those are remaining decisions for the map. The most consequential question surfaced here is whether revision replacement should retain all ink, clear all ink, or explicitly remove a selected subset.
