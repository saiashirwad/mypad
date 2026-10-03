# Shared agent interface and iPad connection

Research resolution for [Find the simplest shared agent interface and iPad connection](https://github.com/saiashirwad/mypad/issues/3), under [Make the iPad a daily canvas for coding agents](https://github.com/saiashirwad/mypad/issues/1). Investigated 2026-10-04. This report makes a recommendation for a later product decision; it does not claim a new transport or installation has been built.

## Finding

Use one globally installed `mypad` command as the portable interface, backed initially by the existing Xcode paired-device mailbox. A fresh `capture` operation followed by the agent's image-reading tool supports the requested “look at my iPad” interaction without waking idle conversations. The same command can be called from any repository. A small MCP adapter is feasible for all three current agent families, but does not replace the iPad transport or eliminate each agent's one-time configuration.

Separate three concerns: the iPad owns the board and handwriting; a bridge places content and captures a particular board state; agent adapters expose those operations. A globally configured tool is available across projects, but it still needs instructions explaining when to invoke it.

## Agent capabilities and discovery

| Agent | Command and image path | Global discovery / MCP |
|---|---|---|
| Codex | Official CLI docs describe running installed local tools and initial `--image` attachments. The installed CLI's `codex --help` confirms `-i, --image`. This research session exposes a local `view_image` tool, so it can inspect the returned PNG during an existing conversation. | MCP configuration defaults to `~/.codex/config.toml`; local stdio and remote servers are supported. A configured tool is discoverable without repo setup. |
| Claude Code | Official image workflow accepts an image path in the conversation. The CLI reference includes Bash among its tools. An agent can run capture, then read/analyze the returned image path. | `--scope user` stores MCP configuration in `~/.claude.json` and exposes it across projects. |
| Pi | Current official `read` source emits PNG and other supported images as image content; `bash` runs shell commands. It accepts relative or absolute paths. Image interpretation requires a vision-capable selected model. | Current upstream supports MCP through a built-in extension and global `~/.pi/agent/mcp.json`, with stdio or streamable HTTP. User instructions and skills also live in the agent directory. |

Sources: [Codex CLI](https://learn.chatgpt.com/docs/codex/cli), [Codex MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli), [Claude CLI reference](https://code.claude.com/docs/en/cli-reference), [Claude images workflow](https://code.claude.com/docs/en/common-workflows#work-with-images), [Claude user MCP scope](https://code.claude.com/docs/en/mcp#user-scope), [Pi CLI](https://github.com/earendil-works/pi/blob/83692682f095528f8b71652ddacff7075e36e893/packages/coding-agent/docs/cli.md), [Pi read implementation](https://github.com/earendil-works/pi/blob/83692682f095528f8b71652ddacff7075e36e893/packages/coding-agent/src/core/tools/read.ts), [Pi MCP](https://github.com/earendil-works/pi/blob/83692682f095528f8b71652ddacff7075e36e893/packages/coding-agent/docs/mcp.md), [Pi configuration](https://github.com/earendil-works/pi/blob/83692682f095528f8b71652ddacff7075e36e893/packages/coding-agent/docs/configuration.md).

Pi's original `badlogic/pi-mono` README now points to `earendil-works/pi`. Older indexed sources claiming Pi has no built-in MCP are stale relative to this inspected upstream commit. No installed Claude/Pi version or cross-agent round trip was tested here. The Codex initial-image flag alone does not establish an existing-session capture workflow in every Codex distribution; test the actual intended client.

For CLI discovery, install once on the Mac's PATH and provide a small user-level instruction/skill per agent: “When asked to look at the iPad, run `mypad capture`, then inspect the image path returned by JSON.” Neither a PATH entry nor a text path in shell output automatically supplies pixels to the model. The image-reading step is essential. With MCP, capture can return image content directly: the [MCP tools specification](https://modelcontextprotocol.io/specification/2025-06-18/server/tools#image-content) permits base64 image results and structured metadata. Actual image fidelity remains a client/model acceptance check.

## Transport evidence

**Existing USB implementation:** [canvas-bridge.py](../scripts/canvas-bridge.py) uses `xcrun devicectl device copy to/from` with `appDataContainer` and the app's bundle ID. Apple’s installed `devicectl` help confirms these file-transfer domains. [Prototype verdict](../prototype/VERDICT.md) records a physical USB placement, annotation, retrieval, and agent-requested capture on 2026-10-04. This research read that evidence and code; it did not repeat the device test.

`capture` creates a UUID command, waits for its acknowledgement, and retrieves that command's immutable export. `pull` instead reads the last deliberate export. These are meaningfully different freshness contracts. Capture is the correct basis for “look now.” The app must be visible and unlocked; the documented export is the canvas viewport, not the OS screen or the entire board. The current bridge is a repo Python script with a hard-coded default device ID and repo-relative export directory, so global packaging still needs work.

**Paired-device Wi-Fi:** Apple documents launching on a paired device over Wi-Fi, Bonjour discovery on the same network, and manual IP connection. This establishes Xcode's supported wireless connection, not successful mailbox transfer on this user's network. The existing bridge delegates transport selection to `devicectl`. Reusing it wirelessly is a plausible next test, not a verified capability. [Apple wireless device guide](https://help.apple.com/xcode/mac/current/en.lproj/dev3e2f4ee6d.html)

USB also uses a network-based device interface in Xcode 15; Apple's technote explains link-local IPv6 and interference from VPN/filtering configuration. Plugging in a cable does not by itself prove that Xcode selected the USB path. [Apple TN3158](https://developer.apple.com/documentation/technotes/tn3158-resolving-xcode-15-device-connection-issues)

**Standalone local Wi-Fi bridge:** A direct app connection can remove the runtime dependency on Xcode device services. It adds service discovery/pairing, authentication, reconnect behavior, and Mac process lifecycle. Apple requires a local-network usage description for apps accessing the local network, and Bonjour service declarations when registering/browsing specific services. Background availability requires separate investigation; the first version can require the canvas to remain open. [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)

## Recommendation and acceptance boundary

For this personal first version, retain the verified mailbox behind a transport boundary and package the command globally. Use USB as the baseline, then test paired Wi-Fi before building a second transport. A standalone bridge becomes justified if measured capture latency, discovery reliability, or Xcode-dependent setup interferes with regular use. The choice is an engineering recommendation, not a claim that devicectl is a general consumer distribution mechanism.

Keep global device selection and default exports outside project repositories; also support an explicit output location inside the current workspace for agents whose filesystem permissions require it. No daemon is necessary for the current mailbox. A later Wi-Fi bridge might be one Mac process shared by all projects. A stdio MCP process is generally client-owned: several agents may start separate adapters, all reaching the same bridge. “One global server” should not conflate global configuration with a singleton process.

Minimum checks before calling the workflow ready:

1. From an unrelated repository, each actual client runs capture and sees the PNG in the ongoing conversation without manual upload or session restart.
2. With USB unplugged, placement and fresh capture succeed, handwriting is visible, and recorded device connection state confirms wireless operation. Repeat after app reopen and Mac/iPad reconnect.
3. Capture IDs correlate with the returned snapshot, failures report offline/app-not-visible clearly, and capture never substitutes a stale latest export.
4. Measure command-to-visible-image latency during ordinary use. Check legibility at real handwriting size; model image resizing can affect it.
5. Until foreground-independent behavior is verified, clearly require MyPad open and iPad unlocked.

No app/device/configuration changes or installs were performed for this research. Only this report was written.
