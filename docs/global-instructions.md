# User-global instruction files

The native **전역 지침** page discovers known user-global instruction files, displays raw Markdown, and provides reviewed creation, editing, and backup restoration. It is separate from the skill library and the CLI/MCP connection. No model login or Keychain access is involved.

## Supported locations

These are candidate files, not proof that a running agent loaded them. Agent versions, compatibility settings, and additional project or managed policies affect the final instructions.

| Agent | Default candidates | Loading notes |
| --- | --- | --- |
| Codex | `~/.codex/AGENTS.override.md`, `~/.codex/AGENTS.md` | First nonempty global file; override takes priority. Honors `CODEX_HOME`. |
| Claude Code | `~/.claude/CLAUDE.md` | User-global memory; project, managed memory and modular rules are separate. Honors `CLAUDE_CONFIG_DIR`. |
| Grok Build | `~/.grok/AGENTS.md`, `CLAUDE.md`, `CLAUDE.local.md`, `AGENT.md` in that directory | Multiple compatible files may be loaded. |
| Antigravity | `~/.gemini/GEMINI.md`, `~/.gemini/AGENTS.md` | User-global instructions; separate rule directories are outside this editor. |
| OpenCode | `~/.config/opencode/AGENTS.md`, `~/.claude/CLAUDE.md` | Own file takes precedence; Claude fallback depends on compatibility settings. Honors `XDG_CONFIG_HOME` for its own file; the fallback ignores `CLAUDE_CONFIG_DIR`. |
| Pi | `~/.pi/agent/AGENTS.override.md`, `AGENTS.md`, `CLAUDE.md` in that directory | First existing candidate takes priority, including an empty file. Honors `PI_CODING_AGENT_DIR`. |
| Cursor | Not provided by this editor | User Rules are managed in Cursor Settings. Its skills and MCP connection remain supported. |
| Devin CLI | Not provided by this editor | A supported user-global file location has not been established here. Its skills and MCP connection remain supported. |

Environment overrides come from the app process. The app does not execute a shell to import shell startup settings. Invalid relative override paths are rejected. Creating an override or an agent's own file can replace the instructions that its fallback previously supplied; inspect the displayed priority guidance before saving.

The first implementation covers the named candidates above. Alternate case spellings on case-sensitive volumes, modular rule directories, project/worktree instructions, managed organization policy, and recursive Markdown imports are outside this editor. There is no automatic synchronization between agents.

Verified loading references:

- [Codex global and project instructions](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Claude Code memory](https://code.claude.com/docs/en/memory)
- [Grok Build project rules](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/12-project-rules.md)
- [Antigravity rules](https://antigravity.google/docs/rules/)
- [OpenCode rules](https://opencode.ai/docs/rules/)
- [Pi resource-loader source](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/src/core/resource-loader.ts)
- [Cursor rules](https://cursor.com/docs/rules)

## Editing and conflicts

Choose an agent, then a file. Existing UTF-8 text is displayed without Markdown rendering. Missing files can be drafted and explicitly created. Discovery and preview do not create instruction directories or files. Read-only files remain readable.

Choose **변경 검토…** or `⌘S`, inspect current and proposed text, the target path and potentially affected agents, then explicitly save. Cancelling leaves the draft intact and writes nothing. The editor preserves a UTF-8 BOM and uniform CRLF line endings when present; backup restoration restores exact previous bytes. Existing permission bits are retained; new files use mode `0600`.

Drafts remain in memory while navigating between files, agents, and app pages. Refresh and app activation preserve dirty drafts. External changes mark the draft stale and disable saving. Copy anything you need to retain before choosing **다시 읽기…**, which explicitly discards the selected draft and reads the current file. Quitting with dirty drafts asks whether to cancel quitting or discard them; drafts are not persisted across quitting or a crash.

The service rechecks candidate paths, file identities, metadata, and bytes before applying a reviewed plan. Changes to other discovered instruction candidates can invalidate a preview, including creation of a higher-priority file. This is conservative conflict detection, not an OS sandbox or a transaction with arbitrary external editors.

## Shared files and limits

Final-file symbolic links are supported when their resolved source is a regular Markdown file inside the user's home. Editing changes the resolved source while retaining the original link and its text. The preview identifies other supported candidate paths resolving to the same source. This list describes potential readers, including compatibility paths; it does not establish which instructions an agent currently uses.

Directory symlinks, outside-home symlink targets, hard links, devices, sockets, FIFOs, unreadable files, invalid UTF-8, and files over 2 MiB are blocked. Regular files at explicitly configured environment paths can be outside the home; final-file link sources cannot. A retargeted or replaced link invalidates a preview. Symbolic links are not converted into standalone copies.

## Private backups and restoration

Before every write, the previous bytes, permission mode, logical path, resolved target path, timestamp, and resulting-content digest are saved under:

```text
~/Library/Application Support/<bundle-id>/InstructionBackups/<UUID>.json
```

The directory is private (`0700`) and backup files use `0600`. A nonblocking lock serializes this app's instruction writes. Backup failure prevents modification. No backup contents are sent to an agent, server, telemetry, or Git. Keep these files private: they contain full instruction text. No automatic backup retention or deletion is implemented; listing is bounded to 1,000 directory entries and rejects an oversized or corrupt store.

**백업 복원** is available only when the current target contents match the saved result of that backup. It opens another before/after preview and rejects external changes. Restoring the backup from a creation removes only the verified newly created file; it leaves its parent directory. Restoration itself creates a backup, allowing another reviewed restoration. Symbolic links remain in place even when their source is restored.

The implementation is in `GlobalInstructions.swift`, `InstructionStore.swift`, and `InstructionViews.swift`. Core tests and the app-state check use temporary homes. The optional native flow test is `scripts/check-settings.sh --instructions`; see [CONTRIBUTING.md](../CONTRIBUTING.md).
