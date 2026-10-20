import AppKit
import SkillCore
import SwiftUI

struct InstructionSidebar: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let editor = store.instructions
        VStack(alignment: .leading, spacing: 12) {
            Button { store.page = .library } label: { Label("스킬 라이브러리", systemImage: "chevron.left") }
                .buttonStyle(.plain).keyboardActivation { store.page = .library }.disabled(editor.busy)
                .accessibilityIdentifier("instructions.back")
                .padding(.bottom, 8)
            Text("전역 지침").font(.headline)
            Text("이 사용자의 모든 프로젝트에 적용되는 지침 파일입니다.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            ForEach(SkillAgent.allCases.filter { $0 != .custom }, id: \.self) { agent in
                let supported = GlobalInstructionService.supportedAgents.contains(agent)
                Button { editor.chooseAgent(agent) } label: {
                    HStack(spacing: 9) {
                        AgentIcon(agent: agent)
                        Text(agent.displayName)
                        Spacer(minLength: 4)
                        if !supported { Text("미지원").font(.caption).foregroundStyle(.secondary) }
                    }.padding(9)
                        .foregroundStyle(WorkbenchTheme.sidebarText)
                        .background(editor.agent == agent ? WorkbenchTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).keyboardActivation { editor.chooseAgent(agent) }.disabled(editor.busy)
                    .accessibilityLabel(agent.displayName + (supported ? ", 전역 지침" : ", 전역 지침 미지원"))
                    .accessibilityAddTraits(editor.agent == agent ? .isSelected : [])
                    .accessibilityIdentifier("instructions.agent." + agent.rawValue)
            }
            Spacer()
            Text("파일 탐지는 현재 에이전트 세션의 지침 로딩을 확인하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
    }
}

struct InstructionFileList: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var editor = store.instructions
        if !editor.supported {
            ContentUnavailableView("전역 지침 미지원", systemImage: "doc.badge.gearshape",
                description: Text(editor.agent == .cursor
                    ? "Cursor의 사용자 전역 규칙은 Cursor 설정에서 관리하세요. 이번 파일 편집 기능에는 포함되지 않습니다."
                    : "Devin CLI의 전역 지침 파일 위치를 확인한 뒤 지원할 예정입니다."))
        } else {
            List(selection: $editor.selectedID) {
                ForEach(editor.agentDocuments.filter {
                    store.search.isEmpty || ($0.url.path + " " + $0.role).localizedCaseInsensitiveContains(store.search)
                }) { document in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(document.url.lastPathComponent, systemImage: document.isLink ? "link" : "doc.text")
                            .fontWeight(.medium)
                        Text(document.role + " · " + document.status).font(.caption).foregroundStyle(.secondary)
                        Text(document.url.displayPath).font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(2).truncationMode(.middle)
                    }.padding(.vertical, 6).tag(document.id)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("instructions.file." + document.agent.rawValue + "." + document.url.lastPathComponent)
                }
            }.listStyle(.inset).scrollContentBackground(.hidden).disabled(editor.busy)
        }
    }
}

struct InstructionDetail: View {
    @Environment(AppStore.self) private var store
    @State private var confirmDiscard = false
    var body: some View {
        let editor = store.instructions
        VStack(alignment: .leading, spacing: 0) {
            if let message = editor.message {
                HStack(alignment: .top) {
                    Label(message, systemImage: "info.circle").font(.callout)
                    Spacer()
                    Button { editor.message = nil } label: { Label("지침 알림 닫기", systemImage: "xmark") }
                        .labelStyle(.iconOnly).buttonStyle(.plain)
                }.padding(16)
                Divider()
            }
            if let document = editor.base, editor.supported {
                header(document)
                Divider()
                if let issue = document.issue {
                    ContentUnavailableView("지침을 읽을 수 없습니다", systemImage: "doc.badge.ellipsis", description: Text(issue))
                } else {
                    if editor.externallyChanged {
                        Label("디스크의 파일이 바뀌었습니다. 초안을 보존했습니다. 다시 읽은 뒤 내용을 합쳐 주세요.", systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(WorkbenchTheme.warning).padding(12)
                    }
                    TextEditor(text: Binding(get: { editor.text }, set: { editor.edit($0) }))
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden).padding(12)
                        .background(WorkbenchTheme.raised)
                        .disabled(editor.busy || !document.isWritable)
                        .accessibilityLabel(editor.agent.displayName + " " + document.url.lastPathComponent + " 지침 편집")
                        .accessibilityIdentifier("instructions.editor")
                    Divider()
                    HStack {
                        Text(editor.hasChanges ? "저장하지 않은 초안" : document.data == nil ? "새 지침 파일" : "Markdown 원문")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("다시 읽기…") { confirmDiscard = true }
                            .disabled(editor.busy || (!editor.hasChanges && !editor.externallyChanged))
                            .accessibilityIdentifier("instructions.reload")
                        Button(document.data == nil ? "파일 생성 검토…" : "변경 검토…") { Task { await editor.prepareSave() } }
                            .disabled(!editor.canSave)
                            .accessibilityIdentifier("instructions.review")
                    }.padding(16)
                }
            } else {
                ContentUnavailableView(editor.supported ? "지침 파일을 선택하세요" : "전역 지침 미지원",
                    systemImage: "text.document", description: Text(editor.supported
                        ? "원문을 확인하거나 파일을 만들어 전역 지침을 관리하세요."
                        : "스킬 관리와 에이전트 연결 기능은 계속 사용할 수 있습니다."))
            }
        }
        .task(id: editor.selectedID) { await editor.loadBackups() }
        .confirmationDialog("초안을 버리고 디스크의 내용으로 다시 읽을까요?", isPresented: $confirmDiscard) {
            Button("초안을 버리고 다시 읽기", role: .destructive) {
                editor.discardDraft()
                Task { await editor.refresh() }
            }
        }
    }

    private func header(_ document: InstructionDocument) -> some View {
        let editor = store.instructions
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(document.url.lastPathComponent).font(.title2.weight(.semibold))
                Spacer()
                if editor.busy { ProgressView().controlSize(.small) }
                Menu("백업 복원") {
                    ForEach(editor.backups) { backup in
                        Button(backup.createdAt.formatted(date: .abbreviated, time: .standard)
                            + (backup.wasCreation ? " · 생성 전" : " · 변경 전")) {
                            Task { await editor.prepareRestore(backup) }
                        }.disabled(backup.savedDigest != document.digest)
                    }
                }.disabled(editor.backups.isEmpty || editor.hasChanges || editor.busy || document.issue != nil)
                    .accessibilityIdentifier("instructions.backups")
                    .help("현재 내용이 백업의 저장 결과와 같은 경우에만 복원할 수 있습니다.")
                Button { NSWorkspace.shared.activateFileViewerSelecting([document.resolvedURL]) } label: {
                    Label("Finder에서 지침 보기", systemImage: "folder")
                }.labelStyle(.iconOnly).disabled(document.data == nil)
            }
            Text(document.url.displayPath).font(.caption.monospaced()).textSelection(.enabled)
            if document.isLink {
                Label("공유 원본: " + document.resolvedURL.displayPath, systemImage: "link")
                    .font(.caption).textSelection(.enabled)
            }
            Text(guidance(editor.agent)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !document.isWritable, document.issue == nil { Label("읽기 전용 파일", systemImage: "lock").font(.caption) }
        }.padding(20)
    }

    private func guidance(_ agent: SkillAgent) -> String {
        switch agent {
        case .codex: "AGENTS.override.md의 비어 있지 않은 지침이 기본 파일보다 우선합니다. 새 우선 파일을 만들면 기존 지침의 적용이 달라집니다."
        case .claudeCode: "사용자 전역 지침입니다. 프로젝트·조직 지침과 rules 폴더의 분리 규칙은 별도로 적용될 수 있습니다."
        case .grokBuild: "전역 지침과 호환 파일을 함께 읽을 수 있습니다. rules 폴더의 분리 규칙은 이 목록에 포함하지 않습니다."
        case .antigravity: "GEMINI.md와 AGENTS.md 전역 지침을 확인합니다. rules 폴더의 분리 규칙은 별도로 관리하세요."
        case .opencode: "기본 AGENTS.md가 없으면 Claude의 전역 파일을 읽을 수 있습니다. 호환 설정에 따라 달라지며, 기본 파일을 만들면 적용이 바뀝니다."
        case .pi: "같은 폴더의 AGENTS.override.md가 우선합니다. 기본 AGENTS.md와 호환 CLAUDE.md의 우선순위를 확인하세요."
        default: ""
        }
    }
}

struct InstructionChangeReview: View {
    let plan: InstructionChangePlan
    let editor: InstructionStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(plan.restoring ? "지침 백업 복원 검토" : "지침 변경 검토").font(.title2.weight(.semibold))
            Text(plan.document.url.displayPath).font(.caption.monospaced()).textSelection(.enabled)
            if plan.document.isLink {
                Label("링크를 보존하고 공유 원본을 수정합니다: " + plan.document.resolvedURL.displayPath, systemImage: "link")
                    .font(.callout)
            }
            Text("영향받을 수 있는 에이전트: " + plan.affectedAgents.map(\.displayName).joined(separator: ", "))
                .font(.callout)
            Text("적용 전 원본을 백업합니다. 확인 후 파일이 바뀌면 적용을 중단합니다.")
                .font(.caption).foregroundStyle(.secondary)
            HSplitView {
                comparison("현재", text: plan.before, missing: plan.document.data == nil)
                comparison(plan.restoring ? "복원 후" : "저장 후", text: plan.after, missing: plan.replacementData == nil)
            }
            if let message = editor.message { Text(message).font(.callout).foregroundStyle(WorkbenchTheme.warning) }
            HStack {
                Spacer()
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction).disabled(editor.busy)
                    .accessibilityIdentifier("instructions.cancel")
                Button(plan.restoring ? "백업 복원" : "지침 저장") {
                    Task { if await editor.apply(plan) { dismiss() } }
                }.keyboardShortcut(.defaultAction).disabled(editor.busy)
                    .accessibilityIdentifier("instructions.apply")
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
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
            }.background(WorkbenchTheme.raised, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel(title + " 지침 내용")
        }.frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity).padding(6)
    }
}
