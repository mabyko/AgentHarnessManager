# Agent logo usage review

Checked: 2026-10-20. This is a review of published evidence for the current assets, not a legal determination or a vendor approval record.

## Summary

| Agent | Evidence for identification use | Remaining point |
| --- | --- | --- |
| Codex | Conditional mark-use terms fit direct service identification | Follow artwork, prominence and attribution rules; no MIT sublicense of the mark |
| Grok Build | Explicit conditional use for accurate service references | Unchanged supplied artwork; no downstream trademark grant |
| Claude Code | Official asset provenance is known | Published policy requires approved materials; no app-specific approval is recorded |
| Antigravity | Google explicitly contemplates compatibility-list icons | Linked general icon guidance requests approval; no specific waiver found |
| OpenCode | Bundled SVGs match assets in the official MIT repository | Upstream copyright and full MIT notice retained in third-party notices; trademark use remains contextual |
| Pi | Press kit describes compact badges and shows an MIT footer | Exact current badge's license scope is partly inferred |
| Devin CLI | Official brand kit encourages reuse context | Public-source redistribution terms are not explicit |
| Cursor | Official kit provides the exact style/appearance variants | Public-source redistribution terms are not explicit |

## Scope and decision rule

Checked on 2026-10-20. This review concerns small agent identity icons next to product names in Agent Harness Manager's supported-agent list and settings, and the corresponding files in a public source repository. It does not cover using those marks as this app's name, app icon, merchandise, or a partnership announcement.

`AgentHarnessManager/AgentIcon.swift` fits official assets into an 18-point frame by default, preserves aspect ratio, and uses supplied colors except Pi's monochrome template rendering. `THIRD_PARTY_NOTICES.md` already separates vendor marks from the project MIT license and disclaims endorsement. These are favorable facts for identification use, not independent grants of asset rights.

Vendor permission, asset copyright licenses, and statutory trademark exceptions answer different questions. For example, the U.S. Ninth Circuit discusses referential trademark use, reasonable necessity, and avoiding implied sponsorship in [Yuga Labs v. Ripps, pp. 34–35](https://cdn.ca9.uscourts.gov/datastore/opinions/2025/07/23/24-879.pdf#page=34). This is a U.S. circuit example, not a worldwide ruling on this app or a copyright license for logo files. A vendor's restrictive policy alone does not prove that every unapproved referential use is unlawful; this review instead records what can be supported under published terms.

## Codex / OpenAI — conditional policy support

[OpenAI's design guidelines](https://openai.com/brand/) permit mark use within their stated conditions, for directly related services, with supplied artwork and ownership acknowledgment. They prohibit misleading affiliation, alterations, and prominence above one's own brand. The permission is non-transferable and revocable.

The current small Codex label is consistent with that stated purpose, subject to those conditions and actual UI presentation. Keep the official asset unchanged and outside the project MIT grant. This does not grant downstream users a sublicense; their use needs its own basis under the vendor terms or applicable law. The source page does not separately grant an unrestricted source-asset redistribution license.

## Grok Build — conditional policy support

[Grok's brand guidelines](https://x.ai/legal/brand-guidelines) allow accurate references to its services under stated conditions, prohibit implying endorsement or using the marks as one's own branding, and require the supplied logo to remain unchanged. Permission can be withdrawn; users cannot grant others rights in the marks.

The current named integration label fits this stated purpose if it remains a truthful description of compatibility. Keep supplied light/dark artwork and rights notices. Public source inclusion must not be described as a project MIT sublicense of the mark. No separate unrestricted asset redistribution license was found on this page.

## Claude Code / Anthropic — prior-approval requirement in policy

[Anthropic's trademark guidelines](https://www.anthropic.com/legal/trademark-guidelines) say marks may be used only as specifically permitted and in materials approved beforehand. They also prohibit alterations and misleading affiliation. The [official extension listing](https://marketplace.visualstudio.com/items?itemName=anthropic.claude-code) establishes where the bundled icon came from; it does not itself establish separate permission for our app.

There is no recorded vendor approval for this app. Do not label the current icon as cleared under Anthropic's published policy solely because it distinguishes an integration. A policy-based release path is to obtain applicable permission or use an independently drawn generic symbol with an accurate plain-text product label. This is not a determination that all unapproved referential trademark use is unlawful.

## Antigravity / Google — relevant compatibility use, approval scope unresolved

The [Antigravity press page](https://antigravity.google/press) supplies the exact full-color product icon. Google's [product co-branding guidance](https://partnermarketinghub.withgoogle.com/brands/google/use-cases/product-co-branding/) explicitly contemplates necessary icons in compatibility lists and contextual product UI, and requires accurate presentation and legal attribution. That supports the intended use category here.

However, its linked [general product-icon guidance](https://partnermarketinghub.withgoogle.com/brands/google/branding-guidelines/how-to-show-googles-brand/#product-icons) directs users to request approval. No clear Antigravity-specific waiver of that process or unrestricted OSS asset grant was found. Do not collapse the favorable compatibility example into confirmed approval. Preserve the official colors and shape; confirm the approval scope before treating the asset as cleared under policy.

## Cursor

**Explicit:** Cursor publishes downloadable brand assets for consistent representation, including separate cube marks and light/dark variants. It identifies 2D as the default logo style and asks that the product be called Cursor. These points support the existing compact cube and product-name presentation. [Official brand guidelines](https://cursor.com/brand)

**Inference / unresolved:** The page provides a practical basis for accurate product identification, but does not expressly license a public GitHub asset copy or sublicensing to downstream users. The linked archive was inspected; no separate license or guideline document was found among its 168 entries. Download availability alone is not a blanket redistribution grant. Cursor's service terms reserve ungranted service rights; they do not provide a separate logo redistribution license. This is a limitation of the evidence, not a finding that integration labels are forbidden. [Official archive](https://ptht05hbb1ssoooe.public.blob.vercel-storage.com/assets/brand/cursor-brand-assets.zip), [service terms, section 5.1](https://cursor.com/en-US/terms-of-service)

## OpenCode

**Explicit copyright permission:** The official repository contains the same light/dark logo SVGs under its root MIT license, copyright 2025 opencode. The bundled SVGs were compared with upstream `opencode-logo-light.svg` and `opencode-logo-dark.svg`: parsed elements, attributes, and path data match; serialization quote characters differ. No narrower license was found in the enclosing source directories. The root license permits copying and distribution with preservation of the upstream copyright and permission notice. [Light asset](https://github.com/anomalyco/opencode/blob/dev/packages/console/app/src/asset/brand/opencode-logo-light.svg), [dark asset](https://github.com/anomalyco/opencode/blob/dev/packages/console/app/src/asset/brand/opencode-logo-dark.svg), [upstream MIT license](https://github.com/anomalyco/opencode/blob/dev/LICENSE)

The brand page also supplies the assets for working with the OpenCode identity. **Inference:** a small icon paired with the supported integration's name fits that stated purpose. Neither this page nor the MIT text establishes endorsement. **Documentation follow-up completed:** `THIRD_PARTY_NOTICES.md` now includes the upstream copyright and full MIT permission notice for these copies. [Brand assets](https://opencode.ai/brand)

## Pi

**Explicit:** The press kit offers the badge for compact uses and displays an MIT License footer. Its primary-logo description covers light/dark editorial placement. This is stronger evidence of intended reuse than an unlabelled downloadable image. [Official press kit](https://pi.dev/press-kit)

**Inference / unresolved:** The footer does not spell out asset-by-asset scope or link a distinct license grant for the current badge. The official archived website repository has an MIT license, copyright 2026 Earendil Inc. and contributors, but its `src/favicon.svg` has different geometry from the currently bundled `pi-badge.svg`; that older repository alone cannot prove coverage of this exact newer badge. The MIT license of the coding-agent software is similarly insufficient to establish the scope of separately hosted artwork. [Archived website license](https://github.com/earendil-works/pi-website/blob/main/LICENSE), [older favicon](https://github.com/earendil-works/pi-website/blob/main/src/favicon.svg)

**Current presentation:** `AgentIcon` applies native template tinting to the Pi asset. No explicit alteration restriction was found on the press-kit page, but that absence is not a separate approval of template rendering. Keep the asset's provenance and any confirmed upstream license notice distinct from this project's own copyright.

## Devin CLI

**Explicit:** Devin's brand page offers official logos, light/dark symbols, transparent PNGs, and a downloadable brand kit. It describes the assets as ready for others' projects. The existing supplied symbol variants therefore have positive first-party reuse context. [Official brand assets](https://devin.ai/brand)

**Inference / unresolved:** Small symbols beside the Devin CLI integration name are consistent with identity use, but the page does not expressly address redistribution of image files inside public open-source repositories or downstream sublicensing. The 66-entry kit contained no separate license or guideline document. Cognition's platform terms reserve its IP and grant service access; they are not an affirmative logo distribution license. Silence in these sources is not proof that this identification use is prohibited. [Official kit](https://devin.ai/assets/brand/brand-kit.zip), [platform terms, sections 2.1 and 3.1](https://cognition.com/legal/platform-terms-of-service)

## Recommended follow-up

- Keep the current contextual presentation: small official symbols beside accurate product names, separate from Agent Harness Manager branding. Preserve proportions, supplied appearance variants, and the existing no-endorsement statement.
- OpenCode’s upstream copyright and full MIT permission notice have been added to `THIRD_PARTY_NOTICES.md`. Keep this notice with source and binary distributions.
- For Claude Code, resolve the prior-approval condition or choose a generic independent symbol before claiming policy clearance. For Antigravity, resolve the linked approval process instead of treating the compatibility example as a waiver.
- Keep Pi, Cursor, and Devin's evidence qualified. Missing explicit public-repository terms are not proof of prohibition. Do not claim that this project's MIT license sublicenses those assets.

The review and third-party attribution have been updated. No logos were replaced, no vendor was contacted, and no repository visibility or remote branches were changed. Policy compliance and possible statutory exceptions should not be presented as the same conclusion.
