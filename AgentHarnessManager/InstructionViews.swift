import AppKit
import SkillCore
import SwiftUI

struct InstructionAgentPicker: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let editor = store.instructions
        Picker("에이전트", selection: Binding(get: { editor.agent }, set: { editor.chooseAgent($0) })) {
            ForEach(SkillAgent.allCases.filter { $0 != .custom }, id: \.self) { agent in
                Label {
                    Text(agent.displayName + (GlobalInstructionService.supportedAgents.contains(agent) ? "" : " (미지원)"))
                } icon: { AgentIcon(agent: agent) }.tag(agent)
            }
        }.pickerStyle(.menu).disabled(editor.busy)
            .accessibilityIdentifier("instructions.agentPicker")
            .help("이 사용자의 모든 프로젝트에 적용되는 지침 파일입니다. 현재 세션의 로딩 여부는 확인하지 않습니다.")
    }
}

struct InstructionFileList: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var editor = store.instructions
        if !editor.supported {
            ContentUnavailableView("전역 지침 미지원", systemImage: "doc.badge.gearshape",
                description: Text(editor.agent == .cursor
                    ? "Cursor의 사용자 전역 규칙은 Cursor 설정에서 관리하세요. 스킬과 에이전트 연결은 계속 사용할 수 있습니다."
                    : "Devin CLI의 전역 지침 파일 위치를 확인한 뒤 지원할 예정입니다. 스킬과 에이전트 연결은 계속 사용할 수 있습니다."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(selection: $editor.selectedID) {
                ForEach(editor.agentDocuments.filter {
                    store.search.isEmpty || ($0.url.path + " " + $0.role).localizedCaseInsensitiveContains(store.search)
                }) { document in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: symbol(document)).accessibilityHidden(true)
                            Text(document.url.lastPathComponent).fontWeight(.medium)
                            Spacer(minLength: 0)
                            if editor.hasDraft(for: document) {
                                Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(WorkbenchTheme.accent)
                            }
                        }.foregroundStyle(document.data == nil && document.issue == nil ? .secondary : .primary)
                        Text(document.role + " · " + status(document)).font(.caption).foregroundStyle(.secondary)
                        if editor.hasDraft(for: document) { Text("저장하지 않은 초안").font(.caption).foregroundStyle(WorkbenchTheme.accent) }
                        Text(document.url.displayPath).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(2).truncationMode(.middle)
                    }.padding(.vertical, 8).tag(document.id)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("instructions.file." + document.agent.rawValue + "." + document.url.lastPathComponent)
                }
            }.listStyle(.inset).scrollContentBackground(.hidden).disabled(editor.busy)
        }
    }
    private func symbol(_ document: InstructionDocument) -> String {
        if document.issue != nil { return "exclamationmark.triangle" }
        if document.isLink { return "link" }
        if !document.isWritable { return "lock.doc" }
        return document.data == nil ? "doc.badge.plus" : "doc.text"
    }
    private func status(_ document: InstructionDocument) -> String {
        if document.issue != nil { return "읽을 수 없음" }
        if document.isLink { return "공유 원본" }
        if !document.isWritable { return "읽기 전용" }
        return document.data == nil ? "없음 · 만들 수 있음" : "있음"
    }
}

struct InstructionDetail: View {
    @Environment(AppStore.self) private var store
    @State private var confirmDiscard = false
    @State private var showGuidance = false

    var body: some View {
        let editor = store.instructions
        VStack(alignment: .leading, spacing: 0) {
            if let message = editor.message {
                HStack(alignment: .top) {
                    Label(message, systemImage: "info.circle").font(.callout)
                    Spacer()
                    Button { editor.message = nil } label: { Label("지침 알림 닫기", systemImage: "xmark") }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                }.padding(16)
                Divider()
            }
            if let document = editor.base, editor.supported {
                header(document)
                Divider()
                if let issue = document.issue {
                    ContentUnavailableView("지침을 읽을 수 없습니다", systemImage: "doc.badge.ellipsis", description: Text(issue))
                } else if document.data == nil && !editor.isCreating {
                    ContentUnavailableView {
                        Label("아직 없는 지침 파일", systemImage: "doc.badge.plus")
                    } description: {
                        Text("필요할 때 새로 만들 수 있습니다. 초안을 작성한 뒤 ‘파일 만들기 검토…’에서 확인해야 실제 파일이 생깁니다.")
                    } actions: {
                        Button("초안 작성", systemImage: "square.and.pencil") { editor.beginCreation() }
                            .buttonStyle(.borderedProminent).disabled(editor.busy)
                            .accessibilityIdentifier("instructions.beginCreation")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if editor.externallyChanged {
                        Label("디스크에서 파일이 바뀌어 저장을 잠갔습니다. 초안을 복사해 보관한 뒤 버리고 다시 읽을 수 있습니다.", systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(WorkbenchTheme.warning).padding(12)
                    } else if document.data == nil {
                        Label("새 파일 초안입니다. 검토하고 저장하기 전까지 파일을 만들지 않습니다.", systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary).padding(12)
                    }
                    TextEditor(text: Binding(get: { editor.text }, set: { editor.edit($0) }))
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden).padding(12)
                        .background(WorkbenchTheme.raised)
                        .disabled(editor.busy || !document.isWritable)
                        .accessibilityLabel(editor.agent.displayName + " " + document.url.lastPathComponent + " 지침 편집")
                        .accessibilityIdentifier("instructions.editor")
                    Divider()
                    footer(document)
                }
            } else {
                ContentUnavailableView(editor.supported ? "지침 파일을 선택하세요" : "전역 지침 미지원",
                    systemImage: "text.document", description: Text(editor.supported
                        ? "원문을 확인하거나 없는 파일의 초안을 작성하세요."
                        : "스킬 관리와 에이전트 연결 기능은 계속 사용할 수 있습니다."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: editor.selectedID) { await editor.loadBackups() }
        .confirmationDialog("초안을 버리고 디스크의 내용으로 돌아갈까요?", isPresented: $confirmDiscard) {
            Button("초안 버리기", role: .destructive) {
                editor.discardDraft()
                Task { await editor.refresh() }
            }
            Button("취소", role: .cancel) {}.keyboardShortcut(.defaultAction)
        } message: { Text("저장하지 않은 초안만 버립니다. 파일을 만들거나 수정하지 않습니다.") }
    }

    private func footer(_ document: InstructionDocument) -> some View {
        let editor = store.instructions
        return HStack(spacing: 10) {
            Label(editor.externallyChanged ? "외부 변경 · 저장 잠김" : editor.isCreating ? "새 파일 초안" : editor.hasChanges ? "저장하지 않은 변경" : "디스크와 같음",
                  systemImage: editor.hasChanges || editor.isCreating ? "circle.fill" : "checkmark")
                .font(.caption).foregroundStyle(editor.hasChanges ? WorkbenchTheme.accent : Color.secondary)
            Spacer(minLength: 8)
            if editor.hasChanges || editor.isCreating || editor.externallyChanged {
                Button("초안 버리기…") { confirmDiscard = true }.buttonStyle(.bordered)
                    .disabled(editor.busy).accessibilityIdentifier("instructions.reload")
                Button(document.data == nil ? "파일 만들기 검토…" : "변경 검토…") { Task { await editor.prepareSave() } }
                    .buttonStyle(.borderedProminent).disabled(!editor.canSave)
                    .help(document.data == nil && editor.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "내용을 입력해야 만들 수 있습니다." : "저장 전 변경 내용과 경로를 검토합니다.")
                    .accessibilityIdentifier("instructions.review")
            } else { Text("UTF-8 · Markdown").font(.caption).foregroundStyle(.secondary) }
        }.padding(14)
    }

    private func header(_ document: InstructionDocument) -> some View {
        let editor = store.instructions
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(document.url.lastPathComponent).font(.title2.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                if editor.busy { ProgressView().controlSize(.small) }
                Menu {
                    ForEach(editor.backups) { backup in
                        Button(backup.createdAt.formatted(date: .abbreviated, time: .standard)
                            + (backup.wasCreation ? " · 생성 전 (파일 없음)" : " · 변경 전")) {
                            Task { await editor.prepareRestore(backup) }
                        }.disabled(backup.savedDigest != document.digest)
                    }
                } label: { Label("백업 복원", systemImage: "clock.arrow.circlepath") }
                    .menuStyle(.borderlessButton).fixedSize()
                    .disabled(editor.backups.isEmpty || editor.hasChanges || editor.busy || !document.isWritable)
                    .accessibilityIdentifier("instructions.backups")
                    .help("현재 파일이 백업의 저장 결과와 일치할 때 복원할 수 있습니다.")
                Button { NSWorkspace.shared.activateFileViewerSelecting([document.resolvedURL]) } label: {
                    Label("Finder에서 지침 보기", systemImage: "folder")
                }.labelStyle(.iconOnly).buttonStyle(.borderless).disabled(document.data == nil)
            }
            Text(document.url.displayPath).font(.caption.monospaced()).textSelection(.enabled).lineLimit(2)
                .help(document.url.path)
            HStack(spacing: 6) {
                Image(systemName: document.isLink ? "link" : !document.isWritable ? "lock" : document.data == nil ? "doc.badge.plus" : "doc.text")
                Text(document.role + " · " + (document.data == nil ? "새 파일 후보" : document.isLink ? "공유 원본" : !document.isWritable ? "읽기 전용" : "기존 파일"))
            }.font(.caption).foregroundStyle(.secondary)
            if document.isLink {
                Text("공유 원본: " + document.resolvedURL.displayPath).font(.caption).textSelection(.enabled)
            }
            DisclosureGroup("우선순위와 적용 범위", isExpanded: $showGuidance) {
                Text(guidance(editor.agent)).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }.font(.caption)
            if let backup = editor.creationUndo {
                HStack(alignment: .top, spacing: 10) {
                    Text("이 앱에서 만든 파일입니다.").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("만들기 되돌리기…", systemImage: "arrow.uturn.backward") {
                        Task { await editor.prepareRestore(backup) }
                    }.buttonStyle(.bordered).controlSize(.small)
                        .accessibilityIdentifier("instructions.undoCreate")
                        .help("검토 후 새 파일을 제거합니다. 제거 전 내용도 백업합니다.")
                }
            }
        }.padding(18)
    }

    private func guidance(_ agent: SkillAgent) -> String {
        switch agent {
        case .codex: "AGENTS.override.md의 비어 있지 않은 지침이 기본 파일보다 우선합니다. 새 우선 파일을 만들면 기존 지침의 적용이 달라집니다."
        case .claudeCode: "사용자 전역 지침입니다. 프로젝트·조직 지침과 rules 폴더의 분리 규칙은 별도로 적용될 수 있습니다."
        case .grokBuild: "전역 지침과 호환 파일을 함께 읽을 수 있습니다. rules 폴더의 분리 규칙은 이 목록에 포함하지 않습니다."
        case .antigravity: "GEMINI.md와 AGENTS.md 전역 지침을 확인합니다. rules 폴더의 분리 규칙은 별도로 관리하세요."
        case .opencode: "기본 AGENTS.md가 없으면 ~/.claude/CLAUDE.md를 읽을 수 있습니다. 호환 설정에 따라 달라지며, 기본 파일을 만들면 적용이 바뀝니다."
        case .pi: "같은 폴더의 AGENTS.override.md가 우선합니다. 빈 우선 파일도 기본 지침을 가릴 수 있으므로 내용을 확인한 뒤 만드세요."
        default: ""
        }
    }
}

struct InstructionChangeReview: View {
    let plan: InstructionChangePlan
    let editor: InstructionStore
    @Environment(\.dismiss) private var dismiss
    private var removesFile: Bool { plan.replacementData == nil }
    private var createsFile: Bool { plan.document.data == nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(removesFile ? "파일 만들기 되돌리기" : createsFile ? "새 지침 파일 만들기" : plan.restoring ? "백업 복원 검토" : "지침 변경 검토")
                .font(.title2.weight(.semibold))
            Text(plan.document.url.displayPath).font(.caption.monospaced()).textSelection(.enabled)
            if plan.document.isLink {
                Label("링크를 보존하고 공유 원본을 수정합니다: " + plan.document.resolvedURL.displayPath, systemImage: "link")
                    .font(.callout)
            }
            Text("영향받을 수 있는 에이전트: " + plan.affectedAgents.map(\.displayName).joined(separator: ", "))
                .font(.callout)
            if removesFile {
                Label("이 앱에서 만든 파일을 제거해 생성 전 상태로 돌아갑니다. 제거 전 내용은 백업하며 상위 폴더는 남깁니다.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(WorkbenchTheme.warning)
            } else if createsFile {
                Text("확인한 경로에 새 파일을 만듭니다. 기존 파일을 덮어쓰지 않으며, 만든 뒤 내용이 같으면 ‘만들기 되돌리기…’로 제거할 수 있습니다.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("적용 전 원본을 백업합니다. 확인 후 파일이 바뀌면 적용을 중단합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HSplitView {
                comparison("현재", text: plan.before, missing: createsFile)
                comparison(removesFile ? "되돌린 후" : plan.restoring ? "복원 후" : "저장 후", text: plan.after, missing: removesFile)
            }
            if let message = editor.message { Text(message).font(.callout).foregroundStyle(WorkbenchTheme.warning) }
            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction).disabled(editor.busy)
                    .accessibilityIdentifier("instructions.cancel")
                if removesFile {
                    Button("새 파일 제거", role: .destructive) { Task { if await editor.apply(plan) { dismiss() } } }
                        .buttonStyle(.bordered).disabled(editor.busy).accessibilityIdentifier("instructions.apply")
                } else {
                    Button(createsFile ? "파일 만들기" : plan.restoring ? "백업 복원" : "변경 저장") {
                        Task { if await editor.apply(plan) { dismiss() } }
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(editor.busy)
                        .accessibilityIdentifier("instructions.apply")
                }
                if editor.busy { ProgressView().controlSize(.small) }
            }
        }.padding(24).frame(minWidth: 760, idealWidth: 900, minHeight: 540, idealHeight: 650)
            .interactiveDismissDisabled(editor.busy)
    }
    private func comparison(_ title: String, text: String, missing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ScrollView([.horizontal, .vertical]) {
                Text(missing ? "(파일 없음)" : text.isEmpty ? "(빈 파일)" : text)
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
            }.background(WorkbenchTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(title + " 지침 내용")
        }.frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity).padding(6)
    }
}
