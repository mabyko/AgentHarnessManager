import SkillCore
import SwiftUI

struct LibrarySidebar: View {
    let newGroup: () -> Void
    @Environment(AppStore.self) private var store
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(LibraryFilter.allCases) { filter in
                            let selected = store.libraryFilter == filter && store.agentFilter == nil && store.groupFilterID == nil && (store.page == .library || store.page == .findings)
                            Button { store.navigate(filter) } label: {
                                VStack(alignment: .leading, spacing: 9) {
                                    HStack {
                                        Image(systemName: filter.symbol)
                                        Spacer()
                                        Text("\(store.count(filter))").monospacedDigit().fontWeight(.semibold)
                                    }
                                    Text(filter.title).font(.caption)
                                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(selected ? WorkbenchTheme.selection : WorkbenchTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? WorkbenchTheme.accent : .clear, lineWidth: 1))
                            }.buttonStyle(.plain)
                                .foregroundStyle(WorkbenchTheme.sidebarText)
                                .accessibilityLabel("\(filter.title), \(store.count(filter))개")
                                .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        sectionTitle("에이전트")
                        ForEach(store.availableAgents, id: \.self) { agent in
                            row(agent.displayName, symbol: "terminal", count: store.skills.filter { $0.installations.contains { $0.location.agent == agent } }.count,
                                selected: store.page == .library && store.agentFilter == agent) { store.navigate(agent: agent) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        sectionTitle("그룹")
                        row("모든 그룹", symbol: "folder", count: store.groups.count, selected: store.page == .groups) { store.page = .groups }
                        ForEach(store.groups) { group in
                            row(group.name, symbol: group.symbol, count: group.skillIDs.count, selected: store.page == .library && store.groupFilterID == group.id) {
                                store.navigate(group: group.id)
                            }
                            .contextMenu {
                                Button("그룹 상세") { store.page = .groups; store.selectedGroupID = group.id }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        sectionTitle("검사")
                        row("검사 이력", symbol: "checkmark.shield", count: store.reviews.count, selected: store.page == .history) { store.page = .history }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        sectionTitle("파일 변경")
                        row("변경 이력", symbol: "arrow.left.arrow.right", count: store.mutations.count, selected: store.page == .changes) { store.page = .changes }
                    }
                    if !store.profiles.isEmpty || store.profilesLoadFailed {
                        VStack(alignment: .leading, spacing: 4) {
                            sectionTitle("보존된 데이터")
                            row("이전 작업 구성", symbol: "archivebox", count: store.profiles.count, selected: store.page == .profiles) { store.page = .profiles }
                        }
                    }
                }.padding(14)
            }
            Divider()
            HStack {
                Button(action: newGroup) { Label("새 그룹", systemImage: "plus") }.buttonStyle(.plain).disabled(!store.metadataIsEditable)
                Spacer()
                Button { openSettings() } label: { Label("설정", systemImage: "gearshape") }.labelStyle(.iconOnly).buttonStyle(.plain)
            }.padding(16)
        }
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(WorkbenchTheme.sidebarSecondary).padding(.bottom, 6)
    }
    private func row(_ title: String, symbol: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 18)
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(.caption).monospacedDigit()
            }.foregroundStyle(WorkbenchTheme.sidebarText).padding(8)
                .background(selected ? WorkbenchTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
