# 앱 아이콘

회색 정리함에 스킬 카드 세 장을 담고 가운데 카드를 파란색으로 강조했다. 내장 image_gen 도구로 원본을 만들고 sips로 배포 크기를 변환했다. 원본은 1254 × 1254 px PNG이며 투명도를 유지한다.

- [Release 원본](release-master.png)
- [개발용 원본](dev-master.png): 동일한 형태에 주황색 D 표시를 추가했다.
- [작은 크기 비교](size-preview.png): 16·32·64 px와 큰 미리보기.
- [Release AppIcon](../../../AgentPluginManager/Assets.xcassets/AppIcon.appiconset)
- [개발용 AppIcon-Dev](../../../AgentPluginManager/Assets.xcassets/AppIcon-Dev.appiconset)

두 빌드의 Bundle ID가 다르므로 아이콘을 구분한다. project.yml의 ASSETCATALOG_COMPILER_APPICON_NAME은 기본 AppIcon, Debug는 AppIcon-Dev다. 기존 아이콘 자산은 없었다. macOS 16·32·128·256·512 pt의 1x/2x 슬롯은 [Apple의 Asset Catalog Format Reference](https://developer.apple.com/library/archive/documentation/Xcode/Reference/xcode_ref-Asset_Catalog_Format/AppIconType.html)에 맞추고, 설치된 Xcode 27의 actool로 두 구성의 컴파일을 확인했다.

## 생성 프롬프트

### Release

Use case: logo-brand. Asset type: production macOS app icon, square high resolution 1024x1024 master. Design one original elegant icon for a local agent skill organizer named Skill Workbench (no lettering in artwork). A pale porcelain rounded-square macOS icon tile, front view with very slight tactile depth, centered and occupying about 84% of the canvas, with real transparent space outside its softly rounded corners. Centered bold glyph: three substantial upright rounded rectangular skill cards gathered into a low dark graphite organizer tray. The middle card is taller and cobalt blue (#3059C7); two shorter cards in cool light gray flank it. Cards look like simple blank modular blocks, no tiny document lines, no code marks. Tray is a clean thick dark U shape embracing the lower part of the cards, like a compact tool organizer. Generous negative space, balanced proportions, refined satin materials and subtle bevels, gentle studio lighting, minimal shadow contained within the icon canvas. Quiet neutral gray and blue palette, crisp silhouette recognizable at 32 pixels. Make the glyph large enough to read clearly, bold forms and no thin outlines. No words, letters, numbers, badges, stars, sparkles, robots, gradients in rainbow colors, or other brand logos. No mockup, no extra icons, no background plane, no frame outside the icon tile. Actual transparent exterior, not checkerboard pixels. One finished icon only.

### 가장자리 정리

Edit target: the supplied macOS icon. Keep the three-card organizer glyph, all proportions, color palette, lighting, porcelain tile, and composition unchanged. Make this a clean production icon cutout: remove ALL detached white specks, stray edge pixels, and cloudy fragments outside the rounded square tile, particularly above and below it. The exterior must be perfectly transparent. Keep the rounded tile boundary smooth, continuous and crisp, with normal gentle antialiasing and no holes or rough cutout edges. Keep the full tile centered with adequate equal transparent margins on all four sides. No added text or symbols. One square icon only. Preserve true alpha transparency.

### Debug 파생

Use case: precise-object-edit. Edit target: this macOS skill-organizer app icon. Create its development-build derivative. Preserve the entire main icon exactly: three upright cards, middle cobalt blue, light gray side cards, graphite tray, pale porcelain rounded tile, framing and lighting. Add only one obvious small orange circular badge within the upper-right corner of the tile, inset from its outer edge and away from the central card glyph. Badge diameter about 20% of tile width, color warm orange #C86A20, one bold white capital letter "D" centered. The badge must stay completely inside the rounded tile silhouette and remain noticeable at a small Dock size. No other lettering or added elements. Keep actual alpha transparency outside the tile. Smooth clean continuous outer boundary, remove any detached dust or white specks outside the tile. One square finished development app icon only.

서비스에 맞춰 다시 만든 [에이전트·SKILL.md 중심 후보](service-candidates/README.md)는 비교용 시안이며 아직 설치 아이콘에 적용하지 않았다.
