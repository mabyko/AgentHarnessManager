import AppKit
import SkillCore
import SwiftUI

struct LibrarySkillDetail: View {
    let skill: CanonicalSkill
    @Environment(AppStore.self) private var store
    @State private var selectedInstallationID: String?
    @State private var editingSource: SkillEntry?
    @State private var document: String?
    @State private var readError: String?
    private var installation: SkillInstallation? { skill.installations.first { $0.id == selectedInstallationID } ?? skill.installations.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if skill.hasProblems {
                    detailSection("검사 결과") {
                        ForEach(skill.installations) { item in
                            ForEach(Array(item.problems.enumerated()), id: \.offset) { _, problem in
                                Label(problem, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(WorkbenchTheme.warning)
                            }
                        }
                    }
                }
                detailSection("설치 위치") {
                    ForEach(skill.installations) { locationCard($0) }
                }
                detailSection("그룹") {
                    let groups = store.groups.filter { $0.skillIDs.contains(skill.id) }
                    if groups.isEmpty { Text("아직 그룹에 속하지 않습니다.").font(.callout).foregroundStyle(.secondary) }
                    ForEach(groups) { group in
                        Button { store.page = .groups; store.selectedGroupID = group.id } label: { Label(group.name, systemImage: group.symbol) }
                    }
                    Menu("그룹에 추가·제외") {
                        ForEach(store.groups) { group in
                            Button((group.skillIDs.contains(skill.id) ? "✓ " : "") + group.name) {
                                var updated = group
                                if !updated.skillIDs.insert(skill.id).inserted { updated.skillIDs.remove(skill.id) }
                                _ = store.saveGroup(updated)
                            }
                        }
                    }.disabled(store.groups.isEmpty || !store.metadataIsEditable)
                }
                detailSection("SKILL.md 원문") {
                    if skill.installations.count > 1 {
                        Picker("읽을 설치 위치", selection: $selectedInstallationID) {
                            ForEach(skill.installations) { Text($0.location.label + " · " + URL(fileURLWithPath: $0.originalPath).lastPathComponent).tag(Optional($0.id)) }
                        }
                    }
                    if let readError { Label(readError, systemImage: "exclamationmark.triangle").foregroundStyle(WorkbenchTheme.warning) }
                    else if let document {
                        Text(document).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            .background(WorkbenchTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                    } else { ProgressView("문서 읽는 중") }
                    Text("문서의 명령을 실행하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(item: $editingSource) { SourceEditorSheet(entry: $0) }
        .task(id: "\(installation?.entry.id ?? ""):\(store.lastScanned?.timeIntervalSince1970 ?? 0)") {
            document = nil; readError = nil
            guard let installation else { return }
            let roots = store.registeredRoots + (installation.disabledRecord.map { [$0.readRoot] } ?? [])
            do {
                let content = try await Task.detached(priority: .userInitiated) {
                    try SkillCatalog.readDocument(entry: installation.entry, approvedRoots: roots)
                }.value
                if !Task.isCancelled { document = content }
            } catch { if !Task.isCancelled { readError = error.localizedDescription } }
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(skill.name).font(.title.weight(.semibold)).textSelection(.enabled)
                Spacer()
                Toggle("전체 설치 켜기", isOn: Binding(get: { skill.installations.allSatisfy(\.isEnabled) }, set: { enabled in
                    Task { await store.prepareChange(title: skill.name, installations: skill.installations, enabled: enabled) }
                })).toggleStyle(.switch).labelsHidden().disabled(!store.canChangeFiles || skill.installations.contains(where: isReadOnly))
            }
            Text(skill.summary).foregroundStyle(.secondary).textSelection(.enabled)
            HStack {
                let enabled = skill.installations.filter(\.isEnabled).count
                Label(enabled == 0 ? "꺼짐" : enabled == skill.installations.count ? "켜짐" : "일부 켜짐", systemImage: enabled == 0 ? "minus.circle" : "checkmark.circle")
                Spacer()
                Button { store.toggleFavorite(skill.id) } label: {
                    Label(store.preferences.favorites.contains(skill.id) ? "즐겨찾기 해제" : "즐겨찾기", systemImage: store.preferences.favorites.contains(skill.id) ? "star.fill" : "star")
                }.disabled(!store.metadataIsEditable)
            }.font(.callout)
        }
    }
    private func isReadOnly(_ item: SkillInstallation) -> Bool {
        item.isSymbolicLink || item.readError != nil
            || !store.automaticRoots.contains(where: { $0.id == item.location.id })
            || URL(fileURLWithPath: item.originalPath).deletingLastPathComponent().path != item.location.url.path
            || skill.installations.contains(where: \.isSymbolicLink)
    }
    private func locationCard(_ item: SkillInstallation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(item.location.label, systemImage: item.isSymbolicLink ? "link" : "folder")
                Spacer()
                Toggle(item.isEnabled ? "켜짐" : "꺼짐", isOn: Binding(get: { item.isEnabled }, set: { enabled in
                    Task { await store.prepareChange(title: item.name + " · " + item.location.label, installations: [item], enabled: enabled) }
                })).toggleStyle(.switch).controlSize(.small).disabled(!store.canChangeFiles || isReadOnly(item))
                    .accessibilityLabel("\(item.location.label), \(item.originalPath), 켜기")
            }.font(.callout.weight(.medium))
            Text(item.currentPath).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            if !item.isEnabled { Text("복원 위치: " + item.originalPath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            if let target = item.resolvedPath { Text("공유 원본: " + target).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button("경로 복사") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.currentPath, forType: .string) }
                Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.currentPath)]) }
            }.font(.caption)
            HStack {
                Text(store.sourceRepository(for: item)?.name ?? "출처 미확인").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("출처 연결…") { editingSource = item.entry }
                    .font(.caption).disabled(!item.isEnabled || store.isScanning || store.sourcesLoadFailed)
            }
            Text(isReadOnly(item) ? "이 설치는 읽기 전용입니다. 기본 경로의 독립된 폴더만 전환할 수 있으며 링크·공유 원본·추가 경로는 보호합니다." : "파일 상태이며 에이전트의 현재 대화에 반영됐는지는 확인하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(14).background(WorkbenchTheme.raised, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct GroupDetail: View {
    let group: SkillGroup
    let edit: () -> Void
    @Environment(AppStore.self) private var store
    @State private var confirmDeletion = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label(group.name, systemImage: group.symbol).font(.title2.weight(.semibold))
                    Spacer()
                    Button("편집", action: edit).disabled(!store.metadataIsEditable)
                }
                HStack {
                    Button("그룹 켜기") { Task { await store.prepareGroupChange(group, enabled: true) } }
                    Button("그룹 끄기") { Task { await store.prepareGroupChange(group, enabled: false) } }
                    Button("스킬 보기") { store.navigate(group: group.id) }
                }.disabled(!store.canChangeFiles || !store.metadataIsEditable)
                Text("스킬 \(group.skillIDs.count)개 · \(store.preferences.activeGroupIDs.contains(group.id) ? "그룹 선택됨" : "그룹 선택 안 됨")").foregroundStyle(.secondary)
                let members = store.skills.filter { group.skillIDs.contains($0.id) }
                ForEach(members) { skill in
                    HStack {
                        Button { store.navigate(); store.selectedSkillID = skill.id } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(skill.name).fontWeight(.medium)
                                Text(skill.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Text(skill.isEnabled ? "켜짐" : "꺼짐").font(.caption).foregroundStyle(.secondary)
                    }.padding(14).background(WorkbenchTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                }
                let missing = group.skillIDs.subtracting(store.skills.map(\.id))
                if !missing.isEmpty {
                    Label("현재 목록에 없는 스킬 \(missing.count)개를 보존하고 있습니다. 복원하거나 그룹 편집에서 제외해 주세요.", systemImage: "exclamationmark.triangle").foregroundStyle(WorkbenchTheme.warning)
                }
                if let profile = store.profiles.first(where: { $0.id == group.id }), !profile.note.isEmpty {
                    detailSection("이전 작업 구성의 메모") { Text(profile.note).textSelection(.enabled) }
                }
                Text("그룹 선택과 설치 위치의 실제 상태는 별개입니다. 편집·삭제는 파일을 바꾸지 않으며, 켜기·끄기에 필요한 파일 변경은 검토 후 적용합니다.").font(.caption).foregroundStyle(.secondary)
                Button("그룹 삭제", role: .destructive) { confirmDeletion = true }.disabled(!store.metadataIsEditable)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("‘\(group.name)’ 그룹을 삭제할까요?", isPresented: $confirmDeletion) {
            Button("그룹 삭제", role: .destructive) { store.deleteGroup(group.id) }
        } message: { Text("그룹만 삭제합니다. 스킬 파일과 이전 작업 구성은 보존합니다.") }
    }
}

struct FindingDetail: View {
    let finding: ReviewFinding
    @Environment(AppStore.self) private var store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Label(finding.title, systemImage: "exclamationmark.triangle").font(.title2.weight(.semibold))
                detailSection("검사 근거") { Text(finding.evidence).textSelection(.enabled) }
                detailSection("대상 위치") { Text(finding.path).font(.system(.callout, design: .monospaced)).textSelection(.enabled) }
                if let hash = finding.contentHash {
                    detailSection("검사한 문서 SHA-256") { Text(hash).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                }
                if let skillID = finding.skillID, store.skills.contains(where: { $0.id == skillID }) {
                    Button("관련 스킬 열기") { store.navigate(); store.selectedSkillID = skillID }
                }
                Text("로컬 파일 접근과 제한된 메타데이터 검사 결과입니다. AI 검토나 에이전트 실행 결과는 포함하지 않습니다.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ReviewDetail: View {
    let record: ReviewRecord
    @Environment(AppStore.self) private var store
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(record.date, format: .dateTime.year().month().day().hour().minute()).font(.title2.weight(.semibold))
                Label(record.provider, systemImage: "checkmark.shield")
                Text("스킬 \(record.skillCount)개 · 확인 필요 \(record.findings.count)건")
                Label(record.snapshotID == store.localReview.snapshotID ? "현재 파일 상태와 일치" : "검사 후 파일·경로 상태가 달라졌습니다", systemImage: record.snapshotID == store.localReview.snapshotID ? "checkmark.circle" : "clock")
                    .foregroundStyle(.secondary)
                ForEach(record.findings) { finding in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(finding.title).font(.headline)
                        Text(finding.evidence).textSelection(.enabled)
                        Text(finding.path).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(WorkbenchTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                }
                if record.findings.isEmpty { Text("이 검사에서 확인이 필요한 문제가 발견되지 않았습니다.").foregroundStyle(.secondary) }
                Text("저장된 검사 시점의 결과입니다. 현재 파일을 다시 읽으려면 새로고침 후 검사하세요.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MutationPreview: View {
    let plan: MutationPlan
    @Environment(AppStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("변경 검토").font(.title2.weight(.semibold))
            Text(plan.title)
            Text("켜기 \(plan.installations.filter(\.enabled).count) · 끄기 \(plan.installations.filter { !$0.enabled }.count)").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(plan.installations) { move in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(move.installation.name + " · " + (move.enabled ? "복원" : "보관"), systemImage: move.enabled ? "arrow.uturn.backward" : "archivebox")
                            Text(move.source + "\n→ " + move.destination).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 320)
            Text("발견 경로 밖의 같은 볼륨에 폴더를 보관하거나 원래 위치로 복원하며 기존 파일을 덮어쓰지 않습니다. 중단되면 기록된 작업을 복구할 수 있습니다. 에이전트의 현재 대화 상태는 바뀌지 않을 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            HStack {
                if store.isMutating { ProgressView().controlSize(.small); Text("적용 중…").font(.caption) }
                Spacer()
                Button("취소") { store.cancelPreview() }.keyboardShortcut(.cancelAction).disabled(store.isMutating)
                Button("적용") { Task { await store.applyPreview() } }.keyboardShortcut(.defaultAction).disabled(store.isMutating)
            }
        }.padding(24).frame(width: 620)
        .interactiveDismissDisabled(store.isMutating)
    }
}

private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        Text(title).font(.headline)
        content()
    }
}
