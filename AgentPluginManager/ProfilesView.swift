import SkillCore
import SwiftUI

struct ProfilesView: View {
    @Environment(AppStore.self) private var store
    @State private var editor: WorkProfile?
    @State private var deletion: WorkProfile?
    @State private var confirmDeletion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("작업 구성").font(.system(size: 29, weight: .semibold))
                        Text("작업에 필요한 스킬을 선택하고 구성으로 저장하세요.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("새 작업 구성", systemImage: "plus") { openEditor(WorkProfile()) }
                        .buttonStyle(.borderedProminent).disabled(!store.profilesAreEditable)
                }
                HStack(spacing: 22) {
                    Label("스킬 \(store.entries.count)개", systemImage: "doc.text")
                    Label("에이전트 \(Set(store.entries.map { store.agentName(for: $0) }).count)개", systemImage: "terminal")
                    Label("작업 구성 \(store.profiles.count)개", systemImage: "slider.horizontal.3")
                }.font(.caption).foregroundStyle(.secondary)
                if let message = store.profileMessage {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(WorkbenchTheme.warning)
                }
                if store.filteredProfiles.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "square.stack.3d.up").font(.system(size: 30)).foregroundStyle(WorkbenchTheme.accent)
                        Text(store.search.isEmpty ? "첫 작업 구성을 만들어 보세요" : "검색한 작업 구성이 없습니다").font(.title3.weight(.semibold))
                        Text("이름을 정하고 설치된 스킬을 선택하면 이곳에 구성 카드가 생깁니다.").foregroundStyle(.secondary)
                        HStack {
                            if !store.search.isEmpty { Button("검색 지우기") { store.search = "" } }
                            Button("스킬 목록 둘러보기") { store.showLibrary() }
                        }
                    }.padding(28).frame(maxWidth: .infinity)
                        .background(WorkbenchTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                        ForEach(store.filteredProfiles) { profileCard($0) }
                    }
                }
                if let profile = store.selectedProfile { profileDetail(profile) }
                else if !store.filteredProfiles.isEmpty {
                    Text("구성 카드를 선택하면 포함된 스킬을 볼 수 있습니다.").foregroundStyle(.secondary)
                }
            }.padding(32)
        }
        .sheet(item: $editor) { ProfileEditor(profile: $0) }
        .confirmationDialog("작업 구성을 삭제할까요?", isPresented: $confirmDeletion, presenting: deletion) { profile in
            Button("구성 삭제", role: .destructive) { store.deleteProfile(profile.id) }
        } message: { profile in
            Text("‘\(profile.name)’ 구성만 삭제합니다. 스킬 파일은 그대로 있습니다.")
        }
    }

    private func openEditor(_ profile: WorkProfile) {
        if !store.profilesLoadFailed { store.profileMessage = nil }
        editor = profile
    }

    private func profileCard(_ profile: WorkProfile) -> some View {
        let selected = profile.id == store.selectedProfileID
        let liveIDs = Set(store.entries.map(\.id))
        let missing = profile.members.filter { !liveIDs.contains($0.id) }.count
        return Button { store.selectedProfileID = profile.id } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(WorkbenchTheme.accent)
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(WorkbenchTheme.accent) }
                }
                Text(profile.name).font(.title3.weight(.semibold)).lineLimit(2)
                Text(profile.note.isEmpty ? "설명 없음" : profile.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack {
                    Text("스킬 \(profile.members.count)개").font(.caption)
                    if missing > 0 { Text("목록에 없음 \(missing)개").font(.caption).foregroundStyle(WorkbenchTheme.warning) }
                }
            }.padding(20).frame(maxWidth: .infinity, minHeight: 145, alignment: .leading)
                .background(selected ? WorkbenchTheme.selection : WorkbenchTheme.raised, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? WorkbenchTheme.accent : WorkbenchTheme.border, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
            .accessibilityLabel("\(profile.name), 스킬 \(profile.members.count)개, 목록에 없음 \(missing)개")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func profileDetail(_ profile: WorkProfile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(profile.name).font(.title2.weight(.semibold))
                    Text("포함된 스킬 \(profile.members.count)개").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("구성 편집") { openEditor(profile) }.disabled(!store.profilesAreEditable)
                Button("구성 삭제", role: .destructive) { deletion = profile; confirmDeletion = true }
                    .disabled(!store.profilesAreEditable)
            }.padding(22)
            Divider()
            if profile.members.isEmpty {
                Text("구성 편집에서 이 작업에 사용할 스킬을 선택하세요.").foregroundStyle(.secondary).padding(22)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(profile.members) { member in
                        let entry = store.entries.first { $0.id == member.id }
                        if let entry {
                            Button { store.selectedEntry = entry } label: { memberRow(member, entry: entry) }
                                .buttonStyle(.plain).help("눌러서 SKILL.md 원문 보기")
                        } else { memberRow(member, entry: nil) }
                        Divider()
                    }
                }
            }
            Label("구성을 선택하거나 저장해도 스킬 파일은 바뀌지 않습니다. 파일에 적용하는 기능은 준비 중입니다.", systemImage: "lock")
                .font(.caption).foregroundStyle(.secondary).padding(18)
        }.background(WorkbenchTheme.raised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(WorkbenchTheme.border, lineWidth: 1))
    }

    private func memberRow(_ member: ProfileMember, entry: SkillEntry?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry?.isSymbolicLink == true ? "link" : "doc.text").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry?.name ?? member.name).font(.callout.weight(.medium))
                Text(member.agentName).font(.caption).foregroundStyle(.secondary)
                Text(entry?.url.displayPath ?? (member.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(entry == nil ? "현재 목록에 없음" : entry?.problem == nil ? "목록에 있음" : "확인 필요")
                .font(.caption).foregroundStyle(entry == nil || entry?.problem != nil ? WorkbenchTheme.warning : .secondary)
            if entry != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
        }.padding(18).contentShape(Rectangle())
    }
}

private struct ProfileEditor: View {
    let profile: WorkProfile
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var note: String
    @State private var selectedIDs: Set<String>
    @State private var query = ""
    @FocusState private var nameFocused: Bool

    init(profile: WorkProfile) {
        self.profile = profile
        _name = State(initialValue: profile.name)
        _note = State(initialValue: profile.note)
        _selectedIDs = State(initialValue: Set(profile.members.map(\.id)))
    }

    private var missingIDs: Set<String> { selectedIDs.subtracting(store.entries.map(\.id)) }
    private var displayedEntries: [SkillEntry] {
        store.entries.filter { query.isEmpty || "\($0.name) \(store.agentName(for: $0)) \($0.url.path)".localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(profile.name.isEmpty ? "새 작업 구성" : "작업 구성 편집").font(.title2.weight(.semibold))
                TextField("구성 이름", text: $name, prompt: Text("작업 이름을 입력하세요"))
                    .textFieldStyle(.roundedBorder).accessibilityLabel("구성 이름").focused($nameFocused)
                TextField("설명", text: $note, prompt: Text("어떤 작업에 사용하는 구성인가요?"))
                    .textFieldStyle(.roundedBorder).accessibilityLabel("구성 설명")
                HStack {
                    Text("스킬 선택").font(.headline)
                    Text("\(selectedIDs.count)개 선택됨").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if store.profiles.contains(where: { $0.id != profile.id }) {
                        Menu("다른 구성에서 가져오기") {
                            ForEach(store.profiles.filter { $0.id != profile.id }) { source in
                                Button("\(source.name) · 스킬 \(source.members.count)개") {
                                    if let ids = store.profileMemberIDs(source.id) { selectedIDs.formUnion(ids) }
                                }
                            }
                        }.disabled(!store.profilesAreEditable)
                    }
                    if !selectedIDs.isEmpty { Button("선택 해제") { selectedIDs.removeAll() } }
                }
                TextField("스킬 검색", text: $query, prompt: Text("이름·에이전트·경로"))
                    .textFieldStyle(.roundedBorder).accessibilityLabel("구성에 넣을 스킬 검색")
                if !missingIDs.isEmpty {
                    HStack {
                        Label("현재 목록에 없는 스킬 \(missingIDs.count)개를 유지합니다.", systemImage: "exclamationmark.triangle").foregroundStyle(WorkbenchTheme.warning)
                        Spacer()
                        Button("구성에서 제외") { selectedIDs.subtract(missingIDs) }
                    }.font(.caption)
                }
                if let message = store.profileMessage { Text(message).font(.caption).foregroundStyle(WorkbenchTheme.warning) }
            }.padding(24)
            Divider()
            List(displayedEntries) { entry in
                Toggle(isOn: Binding(get: { selectedIDs.contains(entry.id) }, set: {
                    if $0 { selectedIDs.insert(entry.id) } else { selectedIDs.remove(entry.id) }
                })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.name).font(.callout.weight(.medium))
                        Text("\(store.agentName(for: entry)) · \(entry.url.displayPath)").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        if let problem = entry.problem { Text(problem).font(.caption).foregroundStyle(WorkbenchTheme.warning) }
                    }
                }.toggleStyle(.checkbox).padding(.vertical, 4)
                    .accessibilityLabel("\(entry.name), \(store.agentName(for: entry)), \(entry.url.displayPath)")
            }.listStyle(.inset)
            Divider()
            HStack {
                Text("저장해도 스킬 파일은 바뀌지 않습니다.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("구성 저장") {
                    if store.saveProfile(id: profile.id, name: name, note: note, memberIDs: selectedIDs) {
                        store.search = ""
                        dismiss()
                    }
                }.keyboardShortcut(.defaultAction)
                    .disabled(!store.profilesAreEditable || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).count > 80 || note.count > 240)
            }.padding(18).background(WorkbenchTheme.raised)
        }.frame(width: 720, height: 640).background(WorkbenchTheme.surface).onAppear { nameFocused = true }
    }
}
