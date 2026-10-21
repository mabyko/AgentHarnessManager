# Workbench and global instruction UX

Implemented direction, 2026-10-21. Preserve the native macOS workbench, existing semantic colors, system typography and agent identity assets. The user task is to inspect and safely change local agent configuration, so clarity and predictable controls take priority over visual effects.

## Decisions

The sidebar contains exactly three task destinations: **스킬 라이브러리**, **전역 지침**, and **활동 이력**. Each has a short contextual summary; instruction drafts and interrupted changes are stated in text. Remove the summary-tile grid, agent filters, individual groups and creation actions from the sidebar. Settings remains in the toolbar and the standard app menu.

Within the skill destination, a native segmented picker switches between **스킬**, **그룹**, and **검사 결과**. The skill list has native menus for status, agent, and group; these compose instead of clearing one another. Registered installation paths, source and link-only controls stay in a disclosure section. A visible result count and reset action explain empty results. The group section retains its mode selector, creation button, membership editing and reviewed file-switch behavior.

Within activity, switch between **요청**, **변경**, and **검사 이력**. Show **보관** only when legacy profiles exist or could not be loaded. Returning to activity opens the last activity section. Re-clicking a selected task preserves its current section, filters and selection; changing tasks clears shared search and library filters. Instruction drafts remain independent of task navigation.

Put instruction-agent selection above the file list, following Settings' skill-path picker. Agent choices and file candidates belong to this task rather than a duplicate tree in the sidebar. Keep all existing page raw values and navigation callers; this is a layout reorganization, not a file-format migration.

Retain candidate priority order rather than separating existing and missing files into reordered groups. Use a plus-document icon and secondary labels for missing candidates, a link for shared sources, and text alongside draft indicators. Collapse detailed loading guidance under **우선순위와 적용 범위** so the editor keeps its working space.

Unsupported and empty states fill their columns. The list header stays at the top, its status stays at the bottom, and the detail message is centered in the available pane.

Treat missing files as optional candidates. **초안 작성** opens an in-memory draft; only **파일 만들기 검토… → 파일 만들기** creates a nonempty file. Show an unsaved-state bar with a clear primary review action. Discard acts on the draft, not the existing file.

Returning to an agent selects its unfinished draft before the default file. An empty creation draft yields to a file discovered on disk; a nonempty draft keeps the existing conflict protection. Discard confirmation defaults to cancellation.

Expose creation undo through the existing reviewed backup mechanism, without adding a new deletion API. The shortcut requires a matching creation record for the same logical file, matching saved contents, no dirty draft/conflict, and a writable direct file path. A removal preview explains the result and backs up the content. Its destructive action is not the Return-key default. Existing files have no arbitrary delete action. See [global instruction safety and limits](../global-instructions.md).

Use one shared navigation-button style for sidebar rows and settings categories. Hover and press change the surface immediately without changing bounds or playing decorative motion. Keep an explicit narrow focus indicator, Button accessibility roles, selected traits, disabled semantics, and the existing keyboard-navigation contract. Scope selectors, filters, save and other actions use standard macOS controls. Do not add gesture-only activation or duplicate click handlers.

## References and adaptation

- [Impeccable](https://github.com/pbakaus/impeccable): its operation-oriented guidance favors familiar controls, restrained surfaces, consistent states and task-focused empty states.
- [taste-skill](https://github.com/Leonxlnx/taste-skill): its app-screen guidance emphasizes information hierarchy and meaningful state rather than decorative dashboard chrome.
- [Lucian UX/UI Prompt](https://lucianlabs.dev/uxui-prompt/): interaction examples inform clear unsaved-state feedback, review steps and discoverable reversal.
- [Lucian Icons](https://lucianlabs.dev/icons/): state changes should have a consistent icon vocabulary. This native app keeps SF Symbols and its existing agent assets rather than adding web SVG components.

These references were inspected as design material. Their scripts, remote dependencies and skill installation instructions are not part of the app.

## Verification

Use synthetic homes for creation, drafts, external conflicts, save, restoration and creation undo. State tests cover destination mapping, last activity, same-task re-selection, combined filters and complete reset. Native tests exercise task navigation, segmented sections, installed-agent filter choices, group creation, the instruction-agent picker, empty-state geometry, nonempty creation guards, existing-file protection, non-default removal, keyboard interaction and light/dark/compact layouts. Fixtures use full-size window content to match the app's toolbar safe area. No personal instruction content belongs in screenshots or the repository. Spoken VoiceOver output and alternate system keyboard-navigation configurations require separate manual verification.
