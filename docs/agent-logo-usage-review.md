# Agent logo usage review

Checked: 2026-10-20. This reviews published policies, relevant legal authorities, and observable open-source practice. It is not a legal determination or a vendor approval record.

## Finding

Small supplied logos beside accurate integration names are a common open-source UI pattern with a plausible identification purpose. The evidence does **not** support a blanket statement that every such logo needs individual advance permission or that all logos must be removed before this project becomes public. Small size and MIT distribution also do not automatically satisfy every vendor policy or resolve artwork copyright.

Missing public-source sublicensing language is an evidence gap, not proof of infringement. Non-transferable brand permission does not let us sublicense a mark, but does not by itself prevent a fork from independently relying on the same published permission or applicable law.

## Project decision

Retain the current supplied identity icons for all eight agents, including Claude Code, Antigravity, and Pi, beside accurate product names in the sidebar and settings. Preserve the supplied artwork and appearance variants, with Pi's existing monochrome template rendering, official source records, ownership attribution, and the independent-project/no-endorsement statement.

This is a contextual identification decision, not a claim of vendor approval or a project MIT sublicense of vendor marks. Anthropic's prior-approval policy, Google's linked approval workflow, and Pi's exact-artwork license scope remain qualified below. Those unresolved points are recorded without treating them as an automatic requirement to remove every icon or block public-source preparation. Review the decision if the asset source, vendor guidance, or a rights-holder request changes.

## Current implementation and scope

[AgentIcon.swift](../AgentHarnessManager/AgentIcon.swift) defaults to an 18-point frame, preserves aspect ratio, and displays an icon beside the product name. Most images use supplied colors; Pi uses monochrome template rendering. These marks identify agents in the sidebar/settings rather than branding the app itself. [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) records official sources, independent-project status, ownership, and an exclusion from the project's own MIT grant; it separately preserves OpenCode's upstream MIT notice.

These are favorable presentation facts, not permission. Installation detection does not itself authorize logo redistribution. An MCP connection likewise does not automatically grant branding rights. This review covers UI display and copying assets into source and release binaries; it does not cover making vendor marks our app icon, product identity, or merchandise.

Three questions must remain separate:

| Question | Relevant evidence | Limit |
| --- | --- | --- |
| Does presentation confuse users about origin or endorsement? | Actual UI and applicable trademark rules | Does not license the image's copyright |
| Does the vendor permit this use? | Brand policy, applicable agreements, any approval | Vendor policy is not itself legislation; contract applicability is a separate question |
| Can the artwork be copied into source/binaries? | Exact provenance, copyright license, any applicable exception | Does not transfer the trademark or permit misleading affiliation |

## Official policy overview

“Unconfirmed” below means adequate evidence was not located, rather than a finding that use is forbidden.

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

## Detailed official-policy evidence

### Claude Code / Anthropic

**Official trademark policy (effective August 1, 2024).** Its coverage expressly includes names, logos, and brand elements. The operative approval language is: “only in materials we approve beforehand.” It also requires supplied imagery, no color/font/proportion changes, clear space/readability, and no implied affiliation or endorsement. No exception for compatibility listings, small icons, nonprofit use, or open-source repositories appears in the published policy. This is evidence that a broad *vendor permission* has not been established; it does not establish that every unapproved identifying use is unlawful. [Anthropic Trademark Guidelines](https://www.anthropic.com/legal/trademark-guidelines).

**Developer / MCP integration does not itself grant branding rights.** The March 16, 2026 Software Directory Terms expressly cover MCP servers, skills, plugins, and apps. Directory listing grants no rights to Anthropic’s name, trademarks, or IP and continues to require its trademark guidelines. This rules out treating an official integration listing as an automatic logo license. [Anthropic Software Directory Terms](https://support.claude.com/en/articles/13145338-anthropic-software-directory-terms).

**The API contract is not a reciprocal logo grant.** Commercial Terms §F reserves IP absent an express grant. §G lets Anthropic identify its customer using the customer’s name/logo; it does not grant customers the reverse permission. These terms govern covered services, rather than supplying a standalone license for Agent Harness Manager’s icon. [Commercial Terms](https://www.anthropic.com/legal/commercial-terms).

**Official asset availability is real, but distinct from reuse terms.** Anthropic’s newsroom links a downloadable press kit, and its official Brandfolder identifies a 13-asset collection. Publicly rendered pages did not reveal a separate permissive source-redistribution license. The newsroom frames the kit as media assets, so availability alone does not resolve embedding in an app/source repository. The Brandfolder static source’s optional user-agreement fields were null; this does not override the trademark policy. [Newsroom](https://www.anthropic.com/news), [official Brandfolder](https://brandfolder.com/anthropic/newsroom).

**Apparently permissive “brand-guidelines” skill is not a logo exception.** Anthropic publishes a style skill discussing colors, typography, and artifact formatting. Its reviewed file contains no Claude logo file, no compatibility-use carve-out, and no logo redistribution grant. An open-source style recipe is not evidence that every brand asset is similarly licensed. [Official skill source](https://raw.githubusercontent.com/anthropics/skills/main/skills/brand-guidelines/SKILL.md).

**Assessment for current use:** a factual, small, subordinate, named icon has a materially different presentation from branding the whole utility as Claude or suggesting partnership. Nevertheless the reviewed official sources do not provide a clear permission route for this exact unapproved bundled logo. A rights-holder inquiry could explicitly cover UI display, release binaries, screenshots, GitHub assets, and ordinary forks. A plain-text label or generic/local-installed-app icon can avoid needing to assert a redistribution license in the meantime. This is a practical options assessment, not a legal prohibition finding.

### Google / Antigravity

**There is an official example matching our UI.** Google’s product co-branding guidance says product icons may be appropriate for a compatible-product grid or an action in product UI; it stresses necessity, context, and no appearance of coming from Google. It also recommends accurate plain-text compatibility statements and legal attribution. Our small named entries fit that *presentation example* better than marketing with the Google corporate logo. However the page does not explicitly say this usage is approval-free or grant source-redistribution rights. [Product co-branding](https://partnermarketinghub.withgoogle.com/brands/google/use-cases/product-co-branding/).

**The linked detailed page still asks for approval.** The “Product icons” section instructs users to create a Partner Marketing Hub account to find assets and request permission through the approval form, with own-brand prominence and adequate context. It then points back to compatibility guidance. Read together, the pages show a permitted design category *within Google’s stated approval workflow*, not a reliable approval exemption. This page repeatedly timed out in web text extraction; its public HTML was retrieved successfully over HTTP and the relevant paragraph verified. [How to show Google’s brand](https://partnermarketinghub.withgoogle.com/brands/google/branding-guidelines/how-to-show-googles-brand/).

**General guidance reinforces the distinction.** Product icons appear under “Ask first,” whereas informational plain-text product references appear among uses that do not need a request. Product-specific rules may matter; no Antigravity-specific exception was found. [Brand Resource Center guidance](https://about.google/brand-resource-center/guidance/).

**An ordinary Google brand approval is narrow.** Its terms condition the limited, royalty-free, non-transferable license on express approval, restricting it to the purpose/materials in the request, requiring ownership attribution, and not creating third-party rights. Consequently an approval for our screenshots or UI should not be assumed to authorize arbitrary public forks, sublicensing under MIT, or standalone logo redistribution. Explicitly describe source/binary/fork distribution when asking. [Google brand terms](https://partnermarketinghub.withgoogle.com/brands/google/trademarks-and-terms/terms-and-conditions/).

**Antigravity has a public press kit, without an included license document.** Its official press page offers full-color, one-color, and white icons in PNG/SVG and a ZIP. The ZIP retrieved during this check contains 12 image files only: six PNGs and six SVGs; no README, LICENSE, text, or PDF. “Press Guidelines” in the site header simply links to that same press page. This demonstrates official assets are available, but not an express MIT-compatible app/source redistribution grant. [Antigravity Press Assets](https://antigravity.google/press), [official ZIP](https://antigravity.google/assets/image/brand/Google-Antigravity-Press-Kit.zip).

**Product terms are not a substitute brand grant.** Antigravity’s Additional Terms incorporate Google’s universal terms; the reviewed additional terms provide no separate icon license. The universal terms’ “Google content” section sends branding/logo users to Brand Permissions. Do not treat installation rights for the application as a logo-redistribution license. [Antigravity Terms](https://antigravity.google/terms), [Google Terms — Google content](https://policies.google.com/terms?hl=en).

**Assessment for current use:** Google expressly recognizes compatibility-icon UI as an appropriate context, so the earlier statement that logos must simply be removed would be too categorical. Nonetheless approval and redistribution scope remain unconfirmed under its published permission route. We can accurately document that uncertainty without asserting illegal use or an inevitable takedown. No reviewed policy states that open-source/noncommercial status alone removes its conditions.

### OpenAI / Codex

**Primary evidence:** [current design guidelines and usage terms](https://openai.com/brand/).

The guidance is addressed to third parties using OpenAI trademarks and copyrighted work in their own materials. It permits mark use within its conditions, directly related to OpenAI services, preserving supplied artwork and acknowledging ownership. It forbids misleading endorsement, greater prominence than the developer's own brand, logo alterations, merchandise, and incorporating the mark into one's own branding. Permission is nonexclusive, nontransferable and revocable. Co-branded partnership materials need approval; the page does not say that every accurate third-party service reference is a partnership. Questions or communications beyond described cases can be referred to its contact.

**Applied judgment:** a small OpenAI symbol next to Codex in a genuine integration list is closer to permitted service reference than co-branding. Preserve official shape/colors/clear space and avoid calling the manager official. No separate blanket MIT license for the artwork was found. The policy itself is a stronger basis than merely taking a logo from the Apache-licensed Codex software repository; Apache licensing of code alone does not grant vendor marks.

### Grok Build

**Primary evidence:** [official brand guidelines, Usage Terms and Logos sections](https://x.ai/legal/brand-guidelines).

The page allows marks only to accurately refer to the vendor or its services, with current guidelines observed. It prohibits unrelated uses, implied sponsorship, inclusion in third-party app titles/domain/product names, and combining marks to create a new identity. Supplied logos must remain unchanged. The vendor may review, require changes or terminate permission; users cannot grant others rights in its marks. Press materials have a separate advance-contact instruction.

**Applied judgment:** named Grok Build integration rows fit the stated reference purpose if truthful. Keep the mark secondary, unmodified and separate from the manager's branding. A release announcement should avoid partnership-style headlines or treating this as a joint product. No separate OSS-artwork grant was found, but these guidelines do not establish a universal advance-approval requirement for every integration icon.

### Cursor

**Primary evidence:** [brand guidelines](https://cursor.com/brand), [Terms of Service §5.1](https://cursor.com/terms-of-service).

The official brand page supplies resources for consistent, accurate Cursor representation and expressly offers separate cube marks, wordmarks, light/dark variants and icon sizes. It prefers the 2D logo style and says the product name is Cursor. Its published text contains no app-specific advance-approval requirement or explicit public-source redistribution clause. The service terms retain service IP and exclude implied service licenses; that clause is not a logo-specific ban and should not erase the brand page's affirmative intended-use context. The general OSS license notice concerns included software components, not a wholesale license for Cursor's own artwork.

**Applied judgment:** current separate 2D cube beside Cursor is well aligned with the kit's presentation guidance. Public source inclusion remains less explicit than OpenCode's matching repository asset license. Do not label the image as our own MIT work; carry source and ownership. Lack of explicit sublicense language is an uncertainty rather than a finding that the use is forbidden.

### Devin CLI

**Primary evidence:** [official Devin/Cognition brand page](https://devin.ai/brand), [Cognition platform terms §3.1 and §3.4](https://cognition.com/legal/platform-terms-of-service).

The brand page provides official logos, symbols, transparent PNGs and source formats, positively invites outside projects, and offers a downloadable kit. The current small Devin symbol is precisely the supplied type of asset. No separate license document or blanket approval requirement is visible on the page. Platform terms reserve service and documentation IP, while §3.4 governs Cognition's use of its customers' marks; that reverse-direction marketing provision should not be misread as the rule governing our contextual Devin icon.

**Applied judgment:** supplied unchanged symbol beside the supported integration has affirmative reuse context. The page does not expressly settle public repository asset redistribution or unrestricted downstream relicensing. Keep the intended identification use and source/ownership clear; do not infer endorsement or a universal prior-permission requirement from unrelated service terms.

### OpenCode

**Primary evidence:** [official brand page](https://opencode.ai/brand), [light SVG](https://github.com/anomalyco/opencode/blob/dev/packages/console/app/src/asset/brand/opencode-logo-light.svg), [dark SVG](https://github.com/anomalyco/opencode/blob/dev/packages/console/app/src/asset/brand/opencode-logo-dark.svg), [root MIT license](https://github.com/anomalyco/opencode/blob/dev/LICENSE).

The official brand page provides assets for use with the OpenCode identity. Existing project review verified the bundled SVG elements, attributes and path data match the upstream light/dark symbols, with only serialization differences; this research did not independently repeat that comparison. The upstream repository's root MIT license grants copyright copying/distribution rights subject to notice preservation, and no narrower enclosing asset license was recorded. This is substantially clearer public-source artwork provenance than software-only licensing or an unscoped footer. The project already retains the upstream notice.

**Applied judgment:** retain the supplied identity symbol and its original MIT notice. Copyright permission does not itself confer a right to imply sponsorship or exclusive ownership of the OpenCode name/mark. Repository URLs track the moving dev branch; pin the actual asset revision for a durable provenance record before finalizing notices.

### Pi

**Primary evidence:** [current official press kit](https://pi.dev/press-kit), [archived official website repository](https://github.com/earendil-works/pi-website), [its MIT license](https://github.com/earendil-works/pi-website/blob/main/LICENSE).

The current page provides editorial logos, a square badge expressly suited to compact uses, downloadable images, and an MIT footer. These support intended reuse, although the press-kit framing specifically addresses coverage and does not spell out app-bundle licensing. The archived website's own MIT license is stronger for assets actually present there, but the current bundled badge was previously compared and found different from its older favicon. The current pi software tree checked via read-only GitHub metadata did not contain a matching badge/website asset. The current Earendil website tree likewise yielded no Pi badge entry. Neither absence is a restriction; it leaves exact-artwork scope unconfirmed.

**Applied judgment:** describing Pi as definitely prohibited is unwarranted; describing the exact current badge as conclusively covered by an unrelated older SVG's MIT license is also unwarranted. Best next evidence would be a matching current source asset under a clear license, or vendor clarification if desired. The current native template tint has no explicit prohibition on this page, but preserving supplied artwork avoids an unnecessary additional assumption.

**Current decision:** retain the current Pi badge for compact agent identification. The official compact-use description, public download and MIT footer provide positive reuse context; incomplete exact-artwork license evidence alone is insufficient reason to replace it. No Pi-specific advance-approval requirement was located in the reviewed page. Orca provides an especially close practice example: its [PiIcon implementation](https://github.com/stablyai/orca/blob/0848dbfcc48cad36de5ce31a16735d2b43934be9/src/renderer/src/lib/agent-icon-glyphs.tsx#L3) explicitly identifies `pi.dev/favicon.svg` as its source and uses `currentColor`, like our monochrome rendering. This supports the product decision without claiming a vendor approval record or unrestricted rights to rebrand the mark.

## Legal authorities: identification matters, with limits

These authorities concern different jurisdictions and facts. None adjudicates these eight logos in this app or supplies a worldwide copyright license.

### Korea: Supreme Court 2001do1355, July 13, 2001

An independent air-filter maker put registered car-model names on packaging to explain applicable vehicles, while clearly identifying its own manufacturer. The Supreme Court upheld the acquittal: in context the markings described purpose rather than the goods' origin, and genuine manufacturer parts were distinguishable. [Official judgment, 2001도1355](https://www.law.go.kr/LSW/precInfoP.do?evtNo=2001%EB%8F%841355).

**Relevance:** compatibility identification can differ from claiming vendor origin. **Limit:** the disputed indications were model names, not a blanket permission for graphical logos or image-file distribution. Accurate labels and our distinct app identity are analogous favorable facts, not a conclusive defense.

### United States: Yuga Labs v. Ripps, Ninth Circuit, July 23, 2025

The court discusses nominative use through identifying the referenced product, using only what is reasonably necessary, and avoiding suggested sponsorship. It rejected that defense for the defendants' own NFT branding; other issues were remanded. This is not a victory for the challenged use. [Official opinion, pp. 34–35](https://cdn.ca9.uscourts.gov/datastore/opinions/2025/07/23/24-879.pdf#page=34).

**Relevance:** a factual agent list differs from using vendor marks as our identity. **Limit:** whether an image is reasonably necessary beyond a readable name remains fact-specific. An 18-point size is not a statutory safe harbor, and a disclaimer is not an automatic cure. A trademark defense is also not a copyright license.

### European Union: BMW v. Deenik, C-63/97, February 23, 1999

The Court of Justice's press summary explains that an independent garage may identify BMW repair/specialist services without falsely suggesting a commercial connection or dealer-network membership. [Court press summary 7/99](https://curia.europa.eu/en/actu/communiques/cp99/cp9907en.htm).

**Relevance:** independence and truthful service identification matter even in a commercial business. **Limit:** the cited document expressly calls itself a nonbinding media summary. This is an analogy under the then-applicable directive, not authorization for our image files. Automated retrieval of the full EUR-Lex text was blocked; no unverified detailed holding is relied on here.

### Copyright: neither all logos nor no logos

The U.S. Copyright Office distinguishes unprotectable names, familiar shapes, and simple combinations from designs with sufficient original expression. Neither “every logo is copyrighted” nor “logos have no copyright” is a sound universal claim. [Circular 33](https://www.copyright.gov/circs/circ33.pdf).

This review does not determine originality, registration, or a copyright exception for each asset. Small size, free distribution, attribution, or an MIT code license alone do not settle that question.

## Actual open-source practice and enforcement

The following are practice examples, not grants of permission. Application code licenses do not establish vendor approval. Source links are pinned to the reviewed commits.

### CodexBar — closest native macOS analogue

CodexBar is an MIT native macOS provider-usage app. Its renderer loads bundled brand resources, including Codex and Claude, and falls back to template SVGs. The source contains `Brand-ProviderIcon-antigravity.png`, `Brand-ProviderIcon-codex.png`, and Claude/Devin/Pi artwork. [MIT license](https://github.com/steipete/CodexBar/blob/9c16d285ff8f6a4078bbaef35de50585a2b6e92f/LICENSE); [renderer](https://github.com/steipete/CodexBar/blob/9c16d285ff8f6a4078bbaef35de50585a2b6e92f/Sources/CodexBar/ProviderBrandIcon.swift#L34); [Claude asset](https://github.com/steipete/CodexBar/blob/9c16d285ff8f6a4078bbaef35de50585a2b6e92f/Sources/CodexBar/Resources/Brand-ProviderIcon-claude.svg).

Its provenance document records official source URLs, exact modifications, and SHA-256 hashes. It explicitly withholds a colored Pi asset because redistribution terms were not established. **Useful convention:** record source, modifications, and unresolved scope separately. It is not a vendor approval certificate. I found no app-specific logo clearance in the reviewed README, root license, and provenance document. [provenance and Pi qualification](https://github.com/steipete/CodexBar/blob/9c16d285ff8f6a4078bbaef35de50585a2b6e92f/docs/provider-brand-icons.md#L36); [Antigravity and Codex provenance](https://github.com/steipete/CodexBar/blob/9c16d285ff8f6a4078bbaef35de50585a2b6e92f/docs/spend-chart-brand-icons.md#L32).

### CC Switch — very close multi-agent management analogue

The MIT application manages Claude Code, Codex and other coding tools. `BrandIcons.tsx` directly imports bundled Claude, OpenAI, and Gemini SVGs; defaults are 16-point icons with product-specific alternative text. The Claude/OpenAI SVGs are physically included in source. [MIT license](https://github.com/farion1231/cc-switch/blob/74cf8e6f0b122dfb59782db045ca03dc1968479e/LICENSE); [imports and product-label icons](https://github.com/farion1231/cc-switch/blob/74cf8e6f0b122dfb59782db045ca03dc1968479e/src/components/BrandIcons.tsx#L7); [bundled Claude](https://github.com/farion1231/cc-switch/blob/74cf8e6f0b122dfb59782db045ca03dc1968479e/src/icons/extracted/claude.svg); [bundled OpenAI](https://github.com/farion1231/cc-switch/blob/74cf8e6f0b122dfb59782db045ca03dc1968479e/src/icons/extracted/openai.svg).

In the reviewed root license, README, component and extracted-icon metadata, I did not locate vendor-specific approval or a logo-specific redistribution license. This is strong evidence that the UI pattern exists in public MIT software, not evidence of permission or risk-free use.

### Chatbox Community Edition — provider-identification assets

Chatbox’s public Community Edition is GPLv3. Its provider-image component asks an asset resolver for a provider ID; the resolver eagerly includes local provider PNGs. Those assets include `claude.png` and `openai.png`. Separate provider components also import several Lobe Icons. [GPLv3 license](https://github.com/ChatboxAI/chatbox/blob/0ac6385ae1ff5bf778777826da3c5edcd55b61b8/LICENSE); [provider-image component](https://github.com/ChatboxAI/chatbox/blob/0ac6385ae1ff5bf778777826da3c5edcd55b61b8/src/renderer/components/icons/ProviderImageIcon.tsx#L27); [bundled asset resolver](https://github.com/ChatboxAI/chatbox/blob/0ac6385ae1ff5bf778777826da3c5edcd55b61b8/src/renderer/utils/providerIconSrc.ts#L6); [Claude PNG](https://github.com/ChatboxAI/chatbox/blob/0ac6385ae1ff5bf778777826da3c5edcd55b61b8/src/renderer/static/icons/providers/claude.png); [OpenAI PNG](https://github.com/ChatboxAI/chatbox/blob/0ac6385ae1ff5bf778777826da3c5edcd55b61b8/src/renderer/static/icons/providers/openai.png); [Lobe imports](https://github.com/ChatboxAI/chatbox/blob/0ac6385ae1ff5bf778777826da3c5edcd55b61b8/src/renderer/components/icons/ProviderIcon.tsx#L1).

The reviewed root license, README and provider-icon files did not document Anthropic/OpenAI permission. Its GPL license governs its source distribution; it does not turn vendor trademark rights into a blanket GPL grant.

### Cherry Studio — provider/model icon catalogue

The application root is standard AGPLv3, confirmed by both LICENSE and README; do not confuse it with a separate similarly named repository using segmented commercial terms. Its UI package metadata says MIT and its source includes provider SVGs plus generated React components, e.g. Anthropic and Claude Code. [root AGPLv3](https://github.com/CherryHQ/cherry-studio/blob/6550a6c9f4cfdcc00cd4c5a7507ff7c4d61851a0/LICENSE); [Community Edition license](https://github.com/CherryHQ/cherry-studio/blob/6550a6c9f4cfdcc00cd4c5a7507ff7c4d61851a0/README.md#L178); [UI package license metadata](https://github.com/CherryHQ/cherry-studio/blob/6550a6c9f4cfdcc00cd4c5a7507ff7c4d61851a0/packages/ui/package.json#L17); [Anthropic SVG](https://github.com/CherryHQ/cherry-studio/blob/6550a6c9f4cfdcc00cd4c5a7507ff7c4d61851a0/packages/ui/icons/providers/light/anthropic.svg); [Claude Code SVG](https://github.com/CherryHQ/cherry-studio/blob/6550a6c9f4cfdcc00cd4c5a7507ff7c4d61851a0/packages/ui/icons/providers/light/claude-code.svg); [generated component](https://github.com/CherryHQ/cherry-studio/blob/6550a6c9f4cfdcc00cd4c5a7507ff7c4d61851a0/packages/ui/src/components/icons/providers/anthropic/light.tsx).

Its package README documents provider/model SVG generation and lookup APIs. I did not locate vendor approval in the reviewed files. The nested package’s MIT metadata is not vendor trademark authorization. A guessed `packages/ui/LICENSE` URL returned 404; no claim of a separate license file is made. [icon pipeline](https://github.com/CherryHQ/cherry-studio/blob/6550a6c9f4cfdcc00cd4c5a7507ff7c4d61851a0/packages/ui/README.md#L210).

### Lobe Icons — common supply chain, not an alternative permission system

This MIT icon collection distributes AI/vendor logos as React/React Native components and SVG/PNG/WebP packages. Its README gives an explicit OpenAI SVG embedding example; the source contains Claude and Claude Code SVGs. [MIT license](https://github.com/lobehub/lobe-icons/blob/8a1b2821bb768c484fe8da20c5e1838b6bf551a9/LICENSE); [distribution formats](https://github.com/lobehub/lobe-icons/blob/8a1b2821bb768c484fe8da20c5e1838b6bf551a9/README.md#L76); [OpenAI embedding example](https://github.com/lobehub/lobe-icons/blob/8a1b2821bb768c484fe8da20c5e1838b6bf551a9/README.md#L280); [Claude SVG](https://github.com/lobehub/lobe-icons/blob/8a1b2821bb768c484fe8da20c5e1838b6bf551a9/packages/static-svg/icons/claude.svg); [Claude Code SVG](https://github.com/lobehub/lobe-icons/blob/8a1b2821bb768c484fe8da20c5e1838b6bf551a9/packages/static-svg/icons/claudecode.svg).

This helps explain how so many integrations ship such icons. Replacing an official asset with its Lobe version does not establish vendor permission. The reviewed root license/README did not provide a per-vendor trademark clearance record. A brand representative’s self-identified permission request for an unrelated FromKai icon shows what explicit submission evidence can look like, but says nothing about Anthropic. [FromKai request](https://github.com/lobehub/lobe-icons/issues/431).

### Simple Icons — useful separation policy and an actual removal episode

Simple Icons’ CC0 repository explicitly distinguishes its overall license from the licenses and trademark conditions of individual icons; it directs users to brand guidelines and has a removal route. This is a stronger model for asset exclusions than simply putting MIT at repository root. [CC0 license](https://github.com/simple-icons/simple-icons/blob/c71c69e3a27e4436936b831c72643e6513b9f49b/LICENSE.md); [icon-specific rights disclaimer](https://github.com/simple-icons/simple-icons/blob/c71c69e3a27e4436936b831c72643e6513b9f49b/DISCLAIMER.md); [permission workflow](https://github.com/simple-icons/simple-icons/blob/c71c69e3a27e4436936b831c72643e6513b9f49b/CONTRIBUTING.md).

Its Claude Code icon [PR #14585](https://github.com/simple-icons/simple-icons/pull/14585) is merged and labelled `permission not needed`. The accessible discussion contains a contributor tagging `@bcherny` for opinion, and a maintainer approval, but **no visible vendor reply or written grant**. This is evidence of another maintainer’s assessment, not Anthropic clearance.

For a concrete enforcement example, a maintainer’s [Microsoft removal issue #11236](https://github.com/simple-icons/simple-icons/issues/11236) reports instructions received from Microsoft’s legal team restricting inclusion to specified unchanged resources. The corresponding [removal PR #10019](https://github.com/simple-icons/simple-icons/pull/10019) was merged on 2024-06-28 (`73c31c01aad169e2ef0b04ced3c9d9f6225f0a8d`). This is a maintainer’s first-hand report plus a source change, not a published court judgment or proof of a comparable AI-vendor demand.

## Recommended approach for Agent Harness Manager

1. **Retain the identification-oriented design.** Small official symbols beside correct product names, with clearly independent app branding, have support in actual OSS practice and identification principles. There is no evidence-based reason here to remove every logo automatically. Do not turn them into our app icon or a partnership lockup.
2. **Keep rights notices precise.** Preserve OpenCode's upstream MIT notice and official source/ownership records for the other marks. Do not claim to sublicense vendor marks under our MIT license. Include applicable notices with release binaries as well as source. A no-endorsement statement communicates independence; it is not permission.
3. **Keep the retained icons' evidence qualified.** Claude has an express prior-approval policy; Google's compatibility examples coexist with an approval workflow. Pi's exact artwork scope remains qualified. The project retains these identifiers for contextual use and does not claim confirmed vendor approval. Revisit individual assets if relevant evidence or vendor guidance changes.
4. **Make provenance durable.** Record exact revisions, retrieval dates, hashes and transformations when refreshing assets. CodexBar offers a useful model. Keep marks replaceable if vendor guidance changes; preserve supplied variants rather than inventing altered colors or shapes. Loading a locally installed application's icon can reduce bundled asset copying, but does not automatically settle trademark presentation.
5. **Treat MIT and free distribution accurately.** No blanket FOSS waiver was found in the restrictive policies. Conversely, missing source-license boilerplate is not enough to declare publication unlawful. A public MIT code project can document third-party assets under their own terms without calling every asset MIT.

If permission is requested, describe UI display, release binaries, screenshots, GitHub source and ordinary forks rather than assuming approval for one image covers all distribution. No vendor contact is needed merely to finish this research, and none was made.

## Verification and limits

Official vendor pages/terms, court or government material, immutable public source examples and first-hand maintainer discussions were checked. The linked Google compatibility and icon pages were read together; HTTP retrieval supplied text where automated extraction timed out. Some EUR-Lex requests were blocked, so the EU discussion is explicitly limited to the court's accessible press summary.

Reviewed application files and bounded issue searches did not establish app-specific Anthropic/Google approval or demands against the four example applications. That does not prove private approvals or complaints do not exist. Policies can change after the check date, and agreements not supplied to this review remain outside scope.

The research record, documentation index, and third-party notice reflect the retained identity icons. This decision does not require a change to the current app implementation.
