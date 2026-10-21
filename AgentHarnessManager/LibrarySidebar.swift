import SkillCore
import SwiftUI

struct LibrarySidebar: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("작업 공간")
                .accessibilityAddTraits(.isHeader)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkbenchTheme.sidebarSecondary)
                .padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 12)
            ForEach(AppDestination.allCases) { destination in
                destinationRow(destination)
            }
            Spacer(minLength: 20)
        }.padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func destinationRow(_ destination: AppDestination) -> some View {
        let selected = store.page.destination == destination
        let status = summary(destination)
        return Button { store.navigate(to: destination) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 17)).frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(destination.title).font(.body.weight(selected ? .semibold : .regular))
                    Text(status).font(.caption).foregroundStyle(WorkbenchTheme.sidebarSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if destination == .instructions && store.instructions.hasDrafts {
                    Image(systemName: "circle.fill").font(.system(size: 6))
                        .foregroundStyle(WorkbenchTheme.accent).padding(.top, 7)
                        .accessibilityHidden(true)
                }
            }.foregroundStyle(WorkbenchTheme.sidebarText)
                .padding(.horizontal, 10).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(SidebarButtonStyle(selected: selected))
            .keyboardActivation { store.navigate(to: destination) }
            .accessibilityLabel(destination.title + ", " + status)
            .accessibilityIdentifier("sidebar." + destination.rawValue)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .padding(.bottom, 6)
    }

    private func summary(_ destination: AppDestination) -> String {
        switch destination {
        case .skills:
            "스킬 \(store.skills.count) · 확인 필요 \(store.currentFindings.count)"
        case .instructions:
            store.instructions.hasDrafts ? "저장하지 않은 초안 있음" : "에이전트별 지침 파일"
        case .activity:
            store.journal.pending != nil ? "중단된 변경 · 복구 필요" : "요청 \(store.agentRequests.count) · 변경 \(store.mutations.count)"
        }
    }
}
