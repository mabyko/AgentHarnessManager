# Third-party references and assets

The app and `SkillCore` currently have no external Swift package dependencies.

The app icons were generated for this project. Their source images and generation prompts are recorded in [the icon notes](docs/design/icons/README.md). Native screenshots and HTML prototypes are project materials; older screenshots show previous names, layouts, and development states.

Codex, Claude Code, Grok Build, Antigravity, OpenCode, Pi, Devin CLI, Cursor, and other named products are referenced to describe connections and agent compatibility. Agent Harness Manager is an independent project and is not endorsed by their vendors.

## Agent identity icons

The `Agent-*.imageset` assets identify supported agents in the sidebar and settings. They are bundled locally; displaying them does not contact the vendors or require an installed agent. Original artwork, aspect ratios, and color variants are retained. The monochrome Pi mark uses native template rendering for light/dark legibility. Other marks use their supplied colors and appearance variants.

These third-party marks remain the property of their respective owners and are **not relicensed under this project's MIT license**. Use them only to identify the corresponding integrations, in accordance with the linked vendor guidance. Do not use them as Agent Harness Manager's app icon or imply endorsement.

The project retains the supplied icons for contextual agent identification alongside accurate product names. This notice records provenance and attribution; it is not a vendor approval record. An open-source release does not waive vendor trademark conditions. The [agent logo usage review](docs/agent-logo-usage-review.md) records this decision, conditional permissions, and unresolved approval or redistribution scope. Anthropic’s published policy requires prior-approved materials; Google’s compatibility guidance links to a general icon approval process. Neither approval is recorded for this app.

Google Antigravity is a trademark of Google LLC. Other product names and marks belong to their respective owners.

Sources retrieved on 2026-10-20:

| Agent / asset | Official source | Bundled files / usage notes |
| --- | --- | --- |
| Codex | [OpenAI's official extension](https://marketplace.visualstudio.com/items?itemName=openai.chatgpt), [icon](https://openai.gallery.vsassets.io/_apis/public/gallery/publisher/openai/extension/chatgpt/latest/assetbyname/Microsoft.VisualStudio.Services.Icons.Default), [brand guidance](https://openai.com/brand/) | `codex-icon.png`, the unchanged OpenAI mark and dark tile used by the official Codex extension. |
| Claude Code | [Anthropic's official extension](https://marketplace.visualstudio.com/items?itemName=anthropic.claude-code), [icon](https://anthropic.gallery.vsassets.io/_apis/public/gallery/publisher/anthropic/extension/claude-code/latest/assetbyname/Microsoft.VisualStudio.Services.Icons.Default), [trademark guidance](https://www.anthropic.com/legal/trademark-guidelines) | `claude-code-icon.png`, unchanged official extension icon. |
| Grok Build | [Brand guidance](https://x.ai/legal/brand-guidelines), [official logo archive](https://data.x.ai/logos/SpaceXAI_Grok_Assets.zip) | `Grok_Logomark_Dark.svg` → `grok-dark.svg` for light backgrounds; `Grok_Logomark_Light.svg` → `grok-light.svg` for dark backgrounds. Artwork unchanged, as required by the guidance. |
| Antigravity | [Press assets](https://antigravity.google/press), [full-color icon](https://antigravity.google/assets/image/brand/antigravity-icon__full-color.svg) | `antigravity.svg`, unchanged full-color symbol. |
| OpenCode | [Brand assets](https://opencode.ai/brand) | `opencode-light.svg` / `opencode-dark.svg`, decoded from the page's official SVG download data URLs. |
| Pi | [Press kit](https://pi.dev/press-kit), [compact badge](https://pi.dev/favicon.svg) | `pi-badge.svg`, the supplied square mark; monochrome template rendering. |
| Devin CLI | [Brand assets](https://devin.ai/brand), [light](https://devin.ai/assets/brand/logos/devin/symbol-light-transparent.png), [dark](https://devin.ai/assets/brand/logos/devin/symbol-dark-transparent.png) | `devin-light.png` / `devin-dark.png`, unchanged transparent symbol variants. |
| Cursor | [Brand guidance](https://cursor.com/brand), [official archive](https://ptht05hbb1ssoooe.public.blob.vercel-storage.com/assets/brand/cursor-brand-assets.zip) | `General Logos/Cube/SVG/CUBE_2D_LIGHT.svg` / `CUBE_2D_DARK.svg` → `cursor-light.svg` / `cursor-dark.svg`; unchanged 2D cube variants for compact display. |

## OpenCode logo artwork — upstream MIT notice

The bundled OpenCode SVG artwork matches the assets in the [official source repository](https://github.com/anomalyco/opencode/tree/dev/packages/console/app/src/asset/brand), covered by its [MIT license](https://github.com/anomalyco/opencode/blob/dev/LICENSE). The following upstream notice applies to these copies. Copyright permission for the artwork does not transfer ownership of the OpenCode trademark or imply endorsement.

```text
MIT License

Copyright (c) 2025 opencode

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
