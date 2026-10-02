# 서비스 중심 아이콘 시안

2026-10-01. 이전의 일반 정리함·모듈 시안 대신 에이전트와 스킬 지침, 작업 구성을 드러내는 후보를 생성했다. 사용자가 B를 선택했으며, 배경을 투명하게 정리한 B를 Release build 4에 적용했다.

[비교 이미지](comparison.png): 위는 큰 모습, 아래는 32·48px 축소 비교다. 아래의 원본은 생성 도구의 결과이며 비교 이미지는 AppKit으로 배치했다.

- A: 명령 프롬프트와 토글로 에이전트의 스킬 구성을 표현한다. 실제 파일 적용 기능은 아직 준비 중이다.
- B: Markdown 지침 문서와 에이전트 표시로 SKILL.md를 모아 관리한다는 의미를 담았다.
- C: Skill의 S와 명령 프롬프트를 결합한 간결한 브랜드 표시다.

회색·흰색과 파란 강조색을 유지한다. B의 배경을 투명하게 정리하고 작은 크기를 확인한 뒤 macOS AppIcon으로 변환했다. [현재 원본과 프롬프트](../README.md)에 기록한다. 이전 후보는 비교 이력으로 보존한다.

## 생성 프롬프트

### A · 에이전트 명령창

```text
Use case: logo-brand. Asset type: one original macOS app-icon concept for Agent Skill Manager, a personal local application that discovers Codex and Claude Code SKILL.md instruction files and organizes skills into work configurations. This is specifically a developer tool for managing CLI-agent instructions, not a generic file organizer or plug-in store. Square high-resolution image, opaque neutral light gray preview background. Center one pale porcelain rounded-square macOS tile with even generous margins. Refined graphite gray and cobalt blue #3059C7 palette, bold clean forms readable at 32 pixels, restrained tactile depth, no rainbow gradients, robots, sparkles, other company logos, microscopic lines, or extra icons. Inside the tile, one large graphite terminal window with a softly rounded rectangle silhouette. A large clear cobalt command-prompt mark ">_" occupies the left half. On the right half, exactly two simple skill-control rows represented by small horizontal pill toggles: one cobalt blue with an ivory knob and one muted gray with an ivory knob, vertically stacked. The prompt and controls form a single integrated bold emblem, visually meaning terminal agents whose capabilities can be configured. No title bar text, no other text, no tiny terminal output. Front view, minimal and sophisticated.
```

### B · 스킬 지침

```text
Use case: logo-brand. Asset type: one original macOS app-icon concept for Agent Skill Manager, a personal local application that discovers Codex and Claude Code SKILL.md instruction files and organizes skills into work configurations. This is specifically a developer tool for managing CLI-agent instructions, not a generic file organizer or plug-in store. Square high-resolution image, opaque neutral light gray preview background. Center one pale porcelain rounded-square macOS tile with even generous margins. Refined graphite gray and cobalt blue #3059C7 palette, bold clean forms readable at 32 pixels, restrained tactile depth, no rainbow gradients, robots, sparkles, other company logos, microscopic lines, or extra icons. Inside the tile, one substantial ivory instruction sheet seated in a graphite folio with three simple visible index tabs. A very large cobalt blue markdown hash symbol "#" is embossed in the center of the sheet, symbolizing SKILL.md instructions. At the lower-right of the folio, a small but bold cobalt rounded-square command-prompt badge with an ivory ">" symbol ties the document to a coding agent. Two glyphs only, no other writing or small lines. Compose as one coherent strong symbol, slightly angled but mostly front-facing. Contemporary restrained macOS rendering, crisp and readable.
```

### C · 스킬 프롬프트

```text
Use case: logo-brand. Asset type: one original macOS app-icon concept for Agent Skill Manager, a personal local application that discovers Codex and Claude Code SKILL.md instruction files and organizes skills into work configurations. This is specifically a developer tool for managing CLI-agent instructions, not a generic file organizer or plug-in store. Square high-resolution image, opaque neutral light gray preview background. Center one pale porcelain rounded-square macOS tile with even generous margins. Refined graphite gray and cobalt blue #3059C7 palette, bold clean forms readable at 32 pixels, restrained tactile depth, no rainbow gradients, robots, sparkles, other company logos, microscopic lines, or extra icons. Inside the tile, a strong original monogram combining capital "S" for Skills with the terminal command-prompt sign ">_". The S is a broad continuous cobalt-blue ribbon with angular cut-ins and softly beveled corners. A compact graphite ">_" sits beside its lower-right opening, visually interlocked into the same emblem, not a separate badge. Only these exact characters "S>_", no other lettering. The mark suggests a skill workbench for coding agents and feels like a memorable developer-tool identity. Simple geometry, mostly flat with subtle satin depth, centered with plentiful negative space. Do not resemble an existing product logo.
```
