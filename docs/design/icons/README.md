# 앱 아이콘: B · 스킬 지침 묶음

2026-10-01 사용자 선택으로 B를 확정했다. 흰 Markdown 지침 문서의 파란 #, 회색 묶음과 파란 명령 프롬프트 배지를 사용한다.

- [Release 원본](release-b-master.png)
- [Debug 원본](dev-b-master.png): 동일 디자인에 주황색 D 표시
- [16·32·64px 비교](size-preview.png)
- [Release AppIcon](../../../AgentSkillManager/Assets.xcassets/AppIcon.appiconset)
- [Debug AppIcon-Dev](../../../AgentSkillManager/Assets.xcassets/AppIcon-Dev.appiconset)

내장 image_gen으로 승인한 B의 외부 배경을 투명하게 정리하고 Debug 파생 이미지를 만들었다. 두 Bundle ID가 달라 아이콘을 구분한다. 자산 카탈로그의 기존 슬롯을 읽어 sips로 크기를 변환했다. project.yml의 기본 AppIcon·Debug AppIcon-Dev 연결은 유지한다. [이전 아이콘 이력과 프롬프트](organizer-history.md), [시안 비교](service-candidates/README.md)는 보존한다. 작은 크기와 두 구성의 자산 컴파일·서명을 검수한다.

## 생성·편집 프롬프트

### 승인한 B 시안

```text
Use case: logo-brand. Asset type: one original macOS app-icon concept for Agent Skill Manager, a personal local application that discovers Codex and Claude Code SKILL.md instruction files and organizes skills into work configurations. This is specifically a developer tool for managing CLI-agent instructions, not a generic file organizer or plug-in store. Square high-resolution image, opaque neutral light gray preview background. Center one pale porcelain rounded-square macOS tile with even generous margins. Refined graphite gray and cobalt blue #3059C7 palette, bold clean forms readable at 32 pixels, restrained tactile depth, no rainbow gradients, robots, sparkles, other company logos, microscopic lines, or extra icons. Inside the tile, one substantial ivory instruction sheet seated in a graphite folio with three simple visible index tabs. A very large cobalt blue markdown hash symbol "#" is embossed in the center of the sheet, symbolizing SKILL.md instructions. At the lower-right of the folio, a small but bold cobalt rounded-square command-prompt badge with an ivory ">" symbol ties the document to a coding agent. Two glyphs only, no other writing or small lines. Compose as one coherent strong symbol, slightly angled but mostly front-facing. Contemporary restrained macOS rendering, crisp and readable.
```

### 배경 투명화

```text
Use case: background-extraction. Edit target: the supplied approved B macOS app icon. Make this exact selected artwork production-ready. Preserve the entire design precisely: pale porcelain rounded square tile, graphite holder, ivory folded Markdown instruction pages, large cobalt blue # mark, blue side tab, and lower-right blue badge with white >. Preserve proportions, composition, colors, material, and lighting. Change only the exterior canvas outside the rounded tile to actual transparent alpha. Remove the gray background plane, shadows outside the tile, and detached stray pixels. Keep the tile edge smooth, continuous and clean with antialiasing; no holes, no clipped icon. Keep equal clear margins. One high-resolution square icon, no extra labels, no new elements, no mockup.
```

### Release 가장자리 정리

```text
Use case: precise-object-edit. Edit target: the supplied approved macOS app icon. Preserve ALL interior artwork exactly: porcelain tile, dark graphite holder, folded ivory pages, cobalt #, side tabs and lower-right blue > badge. Correct ONLY the alpha cutout edge. Eliminate every detached white speck, jagged white fringe, scratch and dust outside the rounded square, especially top and bottom. The rounded tile must have a mathematically smooth continuous silhouette with clean ordinary antialiasing, no ragged pixels, no holes or white fragments. Absolutely transparent exterior, no shadow haze outside the tile, preserve equal margins. Do not change the central symbols, proportions or colors. One square production PNG icon.
```

### Debug 파생

```text
Use case: precise-object-edit. Edit target: the supplied approved macOS app icon. Preserve ALL interior artwork exactly: porcelain tile, dark graphite holder, folded ivory pages, cobalt #, side tabs and lower-right blue > badge. Correct ONLY the alpha cutout edge. Eliminate every detached white speck, jagged white fringe, scratch and dust outside the rounded square, especially top and bottom. The rounded tile must have a mathematically smooth continuous silhouette with clean ordinary antialiasing, no ragged pixels, no holes or white fragments. Absolutely transparent exterior, no shadow haze outside the tile, preserve equal margins. Do not change the central symbols, proportions or colors. One square production PNG icon. Add one development marker: a small warm orange #C86A20 circular badge inset fully INSIDE the upper-right porcelain tile corner with one bold white capital D. Keep it about 17% of tile width, not overlapping the main # or >. Preserve everything else, including true transparent exterior.
```
