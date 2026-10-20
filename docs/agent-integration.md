# Agent CLI and MCP

The app bundles a native `ahm` executable at `Contents/Helpers/ahm`. It shares `SkillCore`, the app's preferences domain, registered discovery roots, and library journal. No external MCP SDK, model account, API key, or Keychain access is needed for these management commands. Authentication stays with the agent; the app has no direct model-provider login.

## Connect an agent

In Settings → **에이전트 연동 · CLI / MCP**, choose **연결 설치…** beside the agent you use. The review sheet shows the exact user configuration path and either a CLI command or the single MCP entry being changed. Existing configuration is backed up privately before applying. Registration never sends an AI request or signs in to a model provider.

Codex, Claude Code, and Grok Build require an installed CLI discoverable in the app's PATH, `~/.local/bin`, `~/.grok/bin`, `/opt/homebrew/bin`, or `/usr/local/bin`. The other five use local configuration edits and do not require their CLI merely to save a registration. The agent still needs to be installed to use it. OpenCode JSONC comments, ordering, and unrelated bytes are preserved; JSON5-only syntax such as unquoted keys is rejected conservatively.

| Agent | Built-in skill roots | User MCP configuration / install method |
| --- | --- | --- |
| Codex | `~/.agents/skills` | `$CODEX_HOME/config.toml`, default `~/.codex/config.toml`; CLI |
| Claude Code | `~/.claude/skills` | `~/.claude.json` or `$CLAUDE_CONFIG_DIR/.claude.json`; CLI |
| Grok Build | `~/.grok/skills` | `$GROK_HOME/config.toml`, default `~/.grok/config.toml`; user-scope CLI |
| Antigravity | `~/.gemini/config/skills` (app/IDE), `~/.gemini/antigravity-cli/skills` (CLI), `~/.gemini/antigravity/skills` (legacy IDE) | `~/.gemini/config/mcp_config.json`; existing legacy `~/.gemini/antigravity/mcp_config.json` is also recognized |
| OpenCode | `~/.config/opencode/skills` | `~/.config/opencode/opencode.json` or existing `opencode.jsonc`, under `mcp` |
| Pi | `~/.pi/agent/skills` | `~/.pi/agent/mcp.json`, under `mcpServers`; requires a Pi version with built-in MCP |
| Devin CLI | `~/.config/devin/skills` | `~/.config/devin/mcp_config.json`; existing legacy `config.json` is recognized when it contains `mcpServers` |
| Cursor | `~/.cursor/skills` | `~/.cursor/mcp.json`, under `mcpServers` |

OpenCode honors absolute `OPENCODE_CONFIG` and `XDG_CONFIG_HOME`; Devin honors `XDG_CONFIG_HOME`; Pi honors absolute `PI_CODING_AGENT_DIR`. These variables come from the app's environment; terminal-only shell settings are not automatically imported into GUI apps. Built-in skill roots remain the standard home locations; register custom profile locations separately for browsing. When competing OpenCode JSON/JSONC or Antigravity current/legacy files exist, the installer refuses to choose automatically. Check which file the agent uses before changing that setup. Devin's dedicated MCP file takes precedence over its legacy main config.

Existing configuration is backed up under `~/Library/Application Support/<bundle-id>/ConnectionBackups/<UUID>/`. Backups may contain sensitive configuration; do not publish them. Foreign or modified same-name registrations, duplicate MCP keys, symlinked file/parent paths, malformed configuration, and edits after preview are rejected. Removal is restricted to this app's exact helper and arguments with no extra environment or working-directory overrides. It preserves other MCP servers and the agent's account. Removal does not restore a whole backup over unrelated later changes.

Settings has separate sidebar categories for General, agent connections, and skill paths. The skill-path page has an agent picker; choose Other Agent to manage custom-agent locations. There are eight supported agent identities and ten built-in roots because Antigravity has multiple locations. Compatibility discovery is represented once: the default `.agents/skills` root can be read by Codex, Grok, OpenCode, Pi, Devin CLI, and Cursor; `.claude/skills` by Claude Code, Grok, and OpenCode. These are documented compatibility locations, conditional on agent version/settings, not proof of actual loading. Shared folders appear under matching agent filters without multiplying installation counts. Detail/preview and CLI plans identify agents affected by a shared-path switch. Root IDs, installation IDs and saved journal records remain stable.

**등록 상태 확인** inspects the saved registration. For the five JSON targets it does not launch the agent, MCP servers, extensions, or an authentication flow. It can report an owned disabled entry. A saved entry does not prove an installed agent, protocol compatibility, policy approval, or live session adoption. Open a new session and inspect its MCP tools after installation (`/mcp` in Claude Code and Pi). Pi's `mcp list` connects enabled servers, so this app deliberately does not use it as a passive status check. Cloud/remote agents are outside this local integration.

For manual registration of the default Release app:

```sh
codex mcp add agent-harness-manager -- \
  "/Applications/Agent Harness Manager.app/Contents/Helpers/ahm" \
  --domain forked.agentskillmanager.local mcp

claude mcp add --scope user --transport stdio agent-harness-manager -- \
  "/Applications/Agent Harness Manager.app/Contents/Helpers/ahm" \
  --domain forked.agentskillmanager.local mcp

grok mcp add --scope user --transport stdio agent-harness-manager -- \
  "/Applications/Agent Harness Manager.app/Contents/Helpers/ahm" \
  --domain forked.agentskillmanager.local mcp
```

Use the actual installed app path and bundle ID if customized. Keep that app path stable after registration. Removing the app bundle leaves agent registrations behind; use **연결 제거…** first or the agent's MCP removal command. Do not restore a whole config backup blindly over later unrelated edits.

Official references: [Codex MCP configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli), [Claude Code MCP scopes and commands](https://code.claude.com/docs/en/mcp), [Grok Build MCP guide](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/07-mcp-servers.md), [Grok skill locations](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/08-skills.md). The existing three CLI command formats are also verified against installed CLI help; the app does not invoke an inference, login, or token-export command.

New-agent official references (checked 2026-10-20): [Antigravity skills](https://antigravity.google/docs/skills), [Antigravity MCP](https://antigravity.google/docs/mcp), [OpenCode skills](https://docs.opencode.ai/docs/skills/), [OpenCode MCP](https://docs.opencode.ai/docs/mcp-servers/), [Pi skills](https://pi.dev/docs/latest/skills), [Pi MCP](https://pi.dev/docs/latest/mcp), [Devin CLI skills](https://docs.devin.ai/cli/extensibility/skills/overview), [Devin MCP](https://docs.devin.ai/cli/extensibility/mcp/configuration), [Cursor skills](https://cursor.com/docs/skills), [Cursor MCP](https://cursor.com/docs/mcp). OpenCode v2.0.32 and `agy` 1.4.3 were detected locally; saving a config has not been treated as live client verification.

## Use the CLI

Copy the CLI path from Settings. It is an executable path, not a shell command; quote paths containing spaces:

```sh
"/Applications/Agent Harness Manager.app/Contents/Helpers/ahm" status
"/Applications/Agent Harness Manager.app/Contents/Helpers/ahm" list --agent codex --limit 20
"/Applications/Agent Harness Manager.app/Contents/Helpers/ahm" list --query writing
"/Applications/Agent Harness Manager.app/Contents/Helpers/ahm" groups
"/Applications/Agent Harness Manager.app/Contents/Helpers/ahm" check
```

`show <installation-id>` reads a registered installation's `SKILL.md`. `plan enable|disable <installation-id>...` previews a change without queuing it. `request enable|disable <installation-id>...` queues an intent for review. Copy the installation IDs from `list`; these commands do not accept arbitrary document paths. `requests` reports queued IDs and their journal-backed state. `help` lists all commands. Ordinary success output is JSON on stdout; failures are JSON on stderr with a nonzero exit status.

`status` roots and `list` installations expose an additive `agents` array of compatibility readers; the original `agent` field remains the primary discovery identity. `plan`/`request` return `affectedAgents` and a shared-path warning when applicable. `list` supports `--query`, `--agent codex|claudeCode|grokBuild|antigravity|opencode|pi|devin|cursor|custom`, `--offset`, and `--limit` (1–100; default 50). Global `--home /absolute/path` and `--domain bundle.id` precede the command and select an alternate local home/preferences domain for testing or custom builds. They are launch options, not MCP tool arguments. The embedded executable infers its enclosing app's bundle ID by default; standalone builds default to the Release domain.

## MCP tools

The `mcp` command uses newline-delimited JSON-RPC over stdin/stdout, negotiates protocol `2025-11-25` or `2025-06-18`, and requires initialize/initialized before tool calls. It starts no HTTP listener. Stdout contains only protocol messages. Unknown methods and invalid protocol arguments return JSON-RPC errors; management failures return tool results with `isError: true`.

- `ahm_status`: registered roots, observed states, counts, pending recovery, snapshot ID.
- `ahm_list`: skills/installation IDs with optional query, agent, offset, limit.
- `ahm_show`: one installation ID's original document and content hash.
- `ahm_check`: existing local metadata/path findings; no LLM, script execution, or saved review-history mutation.
- `ahm_groups`: group definitions and selected group IDs; read-only.
- `ahm_plan`: preview with `installationIDs`, boolean `enabled`, optional `title`.
- `ahm_request`: queue the same intent for human review; does not apply it.
- `ahm_requests`: queued request IDs and observed application state.

No shell, arbitrary file reader, apply, installer, OAuth, or credential tool is exposed. MCP metadata marks local reads as read-only and request submission as a non-destructive, non-idempotent metadata write. Skill text, titles, and results are untrusted data; agents should not follow instructions embedded in them as tool authority. For wire format and lifecycle, see the [official MCP specification](https://modelcontextprotocol.io/specification/2025-11-25).

## Review and apply

1. Ask the agent to inspect installation IDs and prepare a plan or request.
2. Open the app's **에이전트 요청** page. Refocusing the app refreshes the queue; `⌘R` rescans the library and requests.
3. Select a request and choose **현재 상태로 검토…**. The app rescans, checks the snapshot and resource-tree hashes, and reconstructs all paths from its own registered state. Serialized destinations grant no authority.
4. Review every source/destination in the existing change preview. Only **적용** moves files. Cancel preserves them.
5. The request ID becomes the journal operation ID. Completed requests cannot be replayed; interrupted operations use existing recovery. Removing a request from the list preserves applied history and skills.

Requests expire after 24 hours. Changes to documents, resources, group configuration/selection, registered paths, or journal history can invalidate them. A no-op plan queues nothing. At most 100 installation IDs and 100 queued requests are accepted; request files/inbound MCP messages are bounded at 1 MiB. The private request directory uses a process lock, no-follow regular-file reads, and exclusive atomic publication. Corrupt requests are preserved and reported rather than silently overwritten.

Only existing supported default-root installation switches are offered. Shared sources, provider caches, unregistered targets, and custom/nested roots retain their existing protections. Group creation/activation, plugin installation, general MCP/hook/instruction management, and automatic AI review remain outside this first integration. Agents running as your OS user can still edit files through their own tools; app approval controls this management interface, not the whole operating system.

## Verification

`scripts/check-management.sh` runs the actual CLI/MCP subprocess against synthetic skills and an isolated preferences domain. Core tests cover request validation, stale resources, private queue persistence, reviewed config changes, backups, same-name conflicts, and symlink rejection. App-state checks exercise request → rebuilt preview → cancel/apply → journal correlation. Tests use no real credentials or AI requests. Real agent session adoption must still be checked after the user installs the connection.
