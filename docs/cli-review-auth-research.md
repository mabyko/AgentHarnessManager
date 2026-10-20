# CLI review authentication research

Verified on 2026-10-20. This note records current first-party documentation, distinguishes documented behavior from implementation recommendations, and does not constitute an inference or account-login test.

## Scope and project decision

This research covers Codex and Claude Code. Grok Build management support was added separately; its review/authentication policy is not evaluated here. It covers personal local execution, a distributed desktop wrapper, credential handling, shared/server use, and review-process safety. It does not claim to certify every CLI or establish blanket contractual approval. Installed versions inspected: Codex 0.163.0 and Claude Code 2.1.304. Help/version/status commands were used; no inference, login, provider-token extraction, or configuration change was performed. Codex's official status command reports ChatGPT authentication; no raw credential file was opened.

Implementation update: direct ChatGPT connectivity was removed in favor of exposing local management through CLI/MCP. The installed-CLI review adapter discussed here remains a proposal. For Claude, the specific unmodified-binary exception is the relevant product path; a custom subscription OAuth implementation is a different case. App MIT licensing does not waive provider agreements, usage limits, or trademark rules. No CLI review adapter is implemented by this research.

## Claude Code / Anthropic — 2026-10-20

### Documented product boundary

The current [legal and compliance page](https://code.claude.com/docs/en/legal-and-compliance) permits products to run the unmodified published CLI subject to Commercial Terms: preserve its authentication choices, let each user authenticate and pay directly, and do not resell/intermediate usage. It separately prohibits product-owned Claude.ai sign-in and collecting or proxying its session credentials. Its exception expressly preserves users signing into the unchanged CLI with their own subscriptions, including on hosted platforms. Our recommendation is an external installed-CLI subprocess; MIT licensing of our code does not establish redistribution rights for Claude Code or waive these conditions. Branding must avoid implying endorsement.

### Subscription support and remaining ambiguity

The [official support article](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan) explicitly confirms on 2026-10-07 that Agent SDK, `claude -p`, and third-party app usage can still draw subscription limits. It also introduces monthly API credits for Max/Team. Its earlier 2026-06-15 update paused previously announced SDK-usage changes.

The current [Agent SDK overview](https://code.claude.com/docs/en/agent-sdk/overview) and [quickstart](https://code.claude.com/docs/en/agent-sdk/quickstart) retain a broad prior-approval restriction on third-party subscription login/rate-limit offerings. The overview nevertheless recommends `claude -p --output-format json` subprocesses for languages outside Python/TypeScript. This is not fully reconciled with the newer help article. Use the specifically documented unchanged-CLI route; do not present all SDK subscription integrations as approved. A generic hosted model service should use supported API authentication or obtain provider clarification. [Commercial Terms](https://www.anthropic.com/legal/commercial-terms) and [Consumer Terms](https://www.anthropic.com/legal/consumer-terms) remain the applicable agreements.

### Review-process safety and installed CLI evidence

[Programmatic execution documentation](https://code.claude.com/docs/en/headless) supports piping review text to `claude -p`. It warns that ordinary print mode skips workspace trust and can run configured hooks and connect MCP servers before the model starts. **`--bare` is not suitable for reusing a subscription login:** it deliberately does not read OAuth/keychain credentials and requires API-key/provider authentication instead.

The [CLI reference](https://code.claude.com/docs/en/cli-reference) supplies these controls. Installed `claude --help` was read without inference on this machine (reported installed version: 2.1.304):

- `--safe-mode` disables customizations while retaining normal authentication. Managed policy settings, including some policy-configured commands/hooks, still apply; it is not a complete OS sandbox.
- `--tools ""` removes built-in tools. `--allowedTools` only grants approvals and is **not** a tool availability allowlist. MCP tools require separate denial, e.g. `--disallowedTools "mcp__*"`.
- `--strict-mcp-config` with an explicit empty MCP configuration avoids inherited MCP configuration. Managed policy can affect behavior and must not be silently bypassed.
- `--setting-sources` controls user/project/local settings sources. `--settings` overrides only specified keys; an empty object alone does not erase inherited configuration.
- `--no-session-persistence` avoids resumable local transcripts; it does not imply no provider retention or no diagnostic data anywhere.
- `--permission-mode dontAsk` and `--permission-prompts none` deny unresolved approvals; neither substitutes for removing tools/hooks. `--no-chrome` and `--disable-slash-commands` are available too.

Implementation recommendation, not a tested command: send only user-approved text through stdin, use a fresh empty working directory and an explicit executable path, disable model tools and customization loading, verify managed-policy behavior, set time/output limits and cancellation, and avoid placing document contents or credentials in command arguments/logs. Treat the reviewed document as untrusted data, never as instructions to activate tools or follow its embedded prompts. No inference, credential read, or authentication change was performed in this research.

### Billing and credential precedence

The [authentication documentation](https://code.claude.com/docs/en/authentication#authentication-precedence) states that `ANTHROPIC_API_KEY` is **always selected when present in noninteractive print mode**, ahead of stored subscription OAuth. Cloud-provider selection, `ANTHROPIC_AUTH_TOKEN`, `apiKeyHelper`, explicit OAuth-token environment variables, profiles, and gateway policy can also alter the active credential/provider. A subprocess must not blindly inherit arbitrary provider/key/proxy environment variables and then promise subscription billing. Preserve legitimate managed policy, expose the selected connection mode, and fail clearly when it cannot be determined safely.

The same documentation makes Claude Code responsible for credential storage and renewal. Reading macOS Keychain entries or `.credentials.json` ourselves is unnecessary and outside the proposed integration. `CLAUDE_CONFIG_DIR` changes both credential-file location and the Keychain entry; changing it to obtain “isolation” can therefore lose the user's existing login.

### Documentation lookup provenance

Context7 library resolution selected `/websites/code_claude_en_agent-sdk` (official docs, high source reputation), followed by one authentication query. Indexed results covered subprocess execution and API-key setup but did not reconcile the dated subscription-policy changes. The current primary pages above were opened directly to resolve that gap. No third-party OAuth wrapper or unofficial token endpoint is used as evidence.

## Codex / OpenAI — 2026-10-20

### Documented local and product integration

[Non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode) documents scripted `codex exec`, stdin input, JSON/structured output, saved CLI authentication reuse, read-only execution and ephemeral sessions. It also recommends API keys for unattended automation and confines advanced account-auth CI guidance to trusted runners. Its warning against that CI credential-seeding workflow in public/open-source repositories is not a ban on publishing a local CLI wrapper: do not upload a personal auth cache into public CI or distribute it with the app.

[Codex App Server](https://learn.chatgpt.com/docs/app-server) explicitly supports embedding Codex in a product. Its managed ChatGPT mode owns OAuth, token storage and automatic renewal, with account/status RPCs. A native GUI can communicate over stdio without a Python/Node SDK. App-server is version-sensitive; the installed help labels it experimental. Identify the client accurately; the docs request separate known-client registration for integrations intended for enterprise compliance logging. This is not a universal legal certification of all wrappers.

The [authentication guide](https://learn.chatgpt.com/docs/auth) distinguishes subscription authentication from API billing and their respective workspace/data policies. Each user should invoke their own installation and account. Keep CLI credentials owned by Codex; app status and process I/O do not require parsing `auth.json` or reading OS credential-store entries. General-purpose API use, a shared-account hosted service, billing resale and undocumented token relays do not follow automatically from these local-client docs.

### Historical direct ChatGPT connection

The [SIWC quickstart](https://developers.openai.com/siwc/quickstart) and [open-source registration guide](https://developers.openai.com/siwc/token-sharing-open-source/sign-in) separately document dynamic registration, plan-usage scopes and user consent for eligible open-source apps. The [overview](https://developers.openai.com/siwc/token-sharing-open-source) directs paid or remotely hosted offerings to a separate interest process. MIT licensing alone does not establish every user, workspace, geography or distribution's eligibility.

The implementation preserved at commit `4ca6254` contains `ChatGPTProtocol`, `ChatGPTLocalSession` and `ChatGPTConnection` for that direct flow under the app's own issued registration, not the Codex CLI session. Source inspection found no CLI execution, private ChatGPT backend endpoint, or reads of Codex/Claude credential files in these modules. This distinction supports keeping direct ChatGPT connection and local-CLI review as separate modes. Live account eligibility and direct inference are still unverified; prior tests used synthetic credentials/mocks.

### Security boundaries and a proposed adapter

[Sandboxing](https://learn.chatgpt.com/docs/sandboxing) distinguishes approvals from OS file/network restrictions. The app-server contract's read-only access defaults to broad read access; restricted `readableRoots` is a separate control. An empty working directory or `--sandbox read-only` alone does not prove that other files cannot be read. Sandbox restrictions for commands also do not govern every connector/MCP route.

The [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) documents independently controllable command execution, apps, hooks, web/image tools, MCP servers, environment filtering and instruction-loading limits. The [MCP guide](https://learn.chatgpt.com/docs/extend/mcp) explains per-server controls; [hooks](https://learn.chatgpt.com/docs/hooks) can run scripts or MCP calls during lifecycle events, including session startup. Managed policy can enforce behavior; do not silently override or claim to disable it.

Installed `codex exec --help` confirms `--ignore-user-config` leaves authentication on the existing `CODEX_HOME` while skipping the user config. It also confirms `--ephemeral`, `--json`, `--output-schema`, stdin input and sandbox options. Skipping user config is not a complete reset of project/global instruction, hooks, managed policy or tool loading. Changing `CODEX_HOME` as an isolation shortcut can lose the user's normal auth and must not be assumed to preserve login.

For pure text review, prefer model-tool removal as well as restrictive sandboxing. Send user-approved text over stdin, never a shell-interpolated command; use an absolute user-selected executable, a new empty working directory, a fresh ephemeral conversation, explicit provider/auth mode, minimal inherited environment, bounded output/time, cancellation and strict output parsing. Disable unrelated tools, MCP, browser integrations, hooks, skills and automatic instruction discovery using version-verified controls, then validate the effective tool/config surface before enabling review. Reject the run if required isolation conflicts with enforced managed policy. These are implementation acceptance criteria, not a claim that an exact command line has been tested.

## Acceptance criteria before enabling local CLI review

1. Detect and verify the selected executable and supported CLI version without reading raw credentials. Display the actual connection/provider mode and distinguish missing installation, sign-in, policy restriction and usage-limit failures.
2. Preview exactly which document text will leave the device. Treat it as untrusted data; never execute instructions/scripts found in the reviewed skill. A review starts only after explicit user action.
3. Remove model tools for text-only review and separately disable startup hooks, MCP, customizations and browser/connector access. Restrict readable files if any tools remain. Verify effective controls with synthetic adversarial input and an out-of-scope canary file before claiming isolation.
4. Preserve legitimate organizational restrictions. If required hooks or tools cannot be excluded, disclose the mismatch and block this review mode rather than bypassing policy.
5. Filter inherited credential/provider/proxy variables without printing them, preserve necessary managed settings, and avoid promising subscription billing from a login badge alone.
6. Avoid prompt/token text in process arguments or diagnostics. Bound subprocess runtime, stdout/stderr and final JSON; terminate only the owned child process tree on cancellation and report incomplete/failed runs. Ephemeral local sessions do not imply zero provider-side retention.
7. AI output remains a proposal with cited document evidence and an input fingerprint; no automatic skill edits or file activation. Refresh/review again if the source changed.
8. Each user pays and authenticates directly. Do not bundle accounts/tokens, operate a shared subscription relay, modify Claude Code, restrict its built-in auth methods, or imply provider endorsement. Review binary licensing separately if ever rebundling a CLI.

## Result and limits

Both providers document a path for the local installed-CLI design under the conditions above. Claude's unmodified-binary exception and product Commercial Terms are material, and its generic Agent SDK subscription wording remains less clear. Direct SIWC was a separate documented open-source path and is no longer included in the app. This review changed documentation only. No actual skill content was transmitted and no paid/model request was performed. Policies and CLI flags must be rechecked before public release or after a provider/CLI update.
