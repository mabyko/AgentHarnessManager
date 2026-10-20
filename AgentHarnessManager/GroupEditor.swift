import SkillCore
import SwiftUI

struct GroupEditor: View {
    let group: SkillGroup
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedIDs: Set<String>
    @State private var query = ""
    @FocusState private var nameFocused: Bool
    init(group: SkillGroup) {
        self.group = group
        _name = State(initialValue: group.name)
        _selectedIDs = State(initialValue: group.skillIDs)
    }
    private var missingIDs: Set<String> { selectedIDs.subtracting(store.skills.map(\.id)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(group.name.isEmpty ? "새 그룹" : "그룹 편집").font(.title2.weight(.semibold))
            TextField("그룹 이름", text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
                .accessibilityLabel("그룹 이름")
            HStack {
                Text("스킬 \(selectedIDs.count)개 선택").font(.headline)
                Spacer()
                Button("선택 해제") { selectedIDs.removeAll() }
            }
            TextField("스킬 검색", text: $query).textFieldStyle(.roundedBorder)
                .accessibilityLabel("그룹에 넣을 스킬 검색")
            if !missingIDs.isEmpty {
                HStack {
                    Label("목록에 없는 스킬 \(missingIDs.count)개 보존", systemImage: "exclamationmark.triangle")
                    Spacer()
                    Button("그룹에서 제외") { selectedIDs.subtract(missingIDs) }
                }.font(.caption).foregroundStyle(WorkbenchTheme.warning)
            }
            if let message = store.libraryMessage { Text(message).font(.caption).foregroundStyle(WorkbenchTheme.warning) }
            List(store.skills.filter { query.isEmpty || "\($0.name) \($0.summary)".localizedCaseInsensitiveContains(query) }) { skill in
                Toggle(isOn: Binding(get: { selectedIDs.contains(skill.id) }, set: {
                    if $0 { selectedIDs.insert(skill.id) } else { selectedIDs.remove(skill.id) }
                })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(skill.name)
                        Text(skill.installations.map { $0.location.label + " · " + URL(fileURLWithPath: $0.originalPath).lastPathComponent }.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }.toggleStyle(.checkbox).padding(.vertical, 4)
            }.listStyle(.inset)
            HStack {
                Text("그룹 저장은 파일을 변경하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("저장") {
                    if store.saveGroup(SkillGroup(id: group.id, name: name, symbol: group.symbol, skillIDs: selectedIDs)) {
                        store.page = .groups; store.search = ""; dismiss()
                    }
                }.keyboardShortcut(.defaultAction).disabled(!store.metadataIsEditable || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 600, height: 540)
            .onAppear { nameFocused = true }
    }
}
