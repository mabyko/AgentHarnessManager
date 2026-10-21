import AppKit
import Foundation
import Observation
import SkillCore

@MainActor @Observable
final class InstructionStore {
    let service: GlobalInstructionService
    private(set) var documents: [InstructionDocument] = []
    private(set) var backups: [InstructionBackup] = []
    private(set) var agent: SkillAgent = .codex
    var selectedID: String?
    var preview: InstructionChangePlan?
    var message: String?
    private(set) var busy = false
    private(set) var loaded = false
    private var drafts: [String: String] = [:]
    private var bases: [String: InstructionDocument] = [:]

    init(service: GlobalInstructionService) { self.service = service }
    var supported: Bool { GlobalInstructionService.supportedAgents.contains(agent) }
    var agentDocuments: [InstructionDocument] { documents.filter { $0.agent == agent } }
    var selectedDocument: InstructionDocument? { selectedID.flatMap { id in documents.first { $0.id == id } } }
    var base: InstructionDocument? { selectedID.flatMap { bases[$0] } ?? selectedDocument }
    var text: String { get { selectedID.flatMap { drafts[$0] } ?? base?.text ?? "" } }
    var hasChanges: Bool { base.map { text != $0.text } ?? false }
    var hasDrafts: Bool { drafts.contains { id, text in bases[id].map { text != $0.text } ?? false } }
    var externallyChanged: Bool { base?.revision != selectedDocument?.revision }
    var isCreating: Bool { base?.data == nil && selectedID.flatMap { drafts[$0] } != nil }
    var canSave: Bool {
        supported && base?.isWritable == true && hasChanges && !busy && !externallyChanged && preview == nil
            && (base?.data != nil || (isCreating && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    }
    var creationUndo: InstructionBackup? {
        guard let document = selectedDocument, document.data != nil, document.isWritable, !document.isLink,
              !hasChanges, !externallyChanged, !busy else { return nil }
        return backups.first { $0.wasCreation && $0.documentURL == document.url && $0.savedDigest == document.digest }
    }

    func beginCreation() {
        guard base?.data == nil, base?.isWritable == true, !isCreating, !busy else { return }
        edit("")
    }

    func hasDraft(for document: InstructionDocument) -> Bool {
        guard let draft = drafts[document.id], let base = bases[document.id] else { return false }
        return draft != base.text
    }

    func edit(_ text: String) {
        guard let id = selectedID, let document = selectedDocument else { return }
        if bases[id] == nil { bases[id] = document }
        drafts[id] = text
    }

    func chooseAgent(_ value: SkillAgent) {
        guard !busy else { return }
        agent = value
        selectDefault()
        message = nil
    }

    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let service = service
        do {
            let updated = try await Task.detached { try service.scan() }.value
            for document in updated {
                if let draft = drafts[document.id], let base = bases[document.id],
                   draft != base.text || (base.data == nil && document.data == nil) { continue }
                drafts.removeValue(forKey: document.id)
                bases.removeValue(forKey: document.id)
            }
            documents = updated
            loaded = true
            if !agentDocuments.contains(where: { $0.id == selectedID }) { selectDefault() }
        } catch { message = error.localizedDescription }
    }

    func loadBackups() async {
        guard let document = selectedDocument else { backups = []; return }
        let service = service
        do {
            let result = try await Task.detached { try service.backups(for: document) }.value
            if selectedID == document.id { backups = result }
        } catch { if selectedID == document.id { backups = []; message = error.localizedDescription } }
    }

    func discardDraft() {
        guard let id = selectedID, !busy else { return }
        drafts.removeValue(forKey: id)
        bases.removeValue(forKey: id)
        message = nil
    }

    func prepareSave() async {
        guard canSave, let document = base else { return }
        let text = text, service = service
        busy = true
        defer { busy = false }
        do { preview = try await Task.detached { try service.prepare(document, text: text) }.value; message = nil }
        catch { message = error.localizedDescription }
    }

    func prepareRestore(_ backup: InstructionBackup) async {
        guard !busy, !hasChanges, let document = base else { return }
        let service = service
        busy = true
        defer { busy = false }
        do { preview = try await Task.detached { try service.prepareRestore(document, backupID: backup.id) }.value; message = nil }
        catch { message = error.localizedDescription }
    }

    func apply(_ plan: InstructionChangePlan) async -> Bool {
        guard !busy else { return false }
        let service = service
        busy = true
        do {
            _ = try await Task.detached { try service.apply(plan) }.value
            drafts.removeValue(forKey: plan.document.id)
            bases.removeValue(forKey: plan.document.id)
            preview = nil
            busy = false
            await refresh()
            await loadBackups()
            message = plan.restoring && plan.replacementData == nil ? "새 파일 만들기를 되돌렸습니다."
                : plan.restoring ? "백업을 복원했습니다. 새 에이전트 세션에서 지침을 확인하세요."
                : "지침을 저장했습니다. 새 에이전트 세션에서 지침을 확인하세요."
            return true
        } catch { busy = false; message = error.localizedDescription; return false }
    }

    private func selectDefault() {
        selectedID = agentDocuments.first(where: { drafts[$0.id] != nil })?.id
            ?? agentDocuments.first(where: { $0.data != nil })?.id
            ?? agentDocuments.first(where: { $0.url.lastPathComponent == "AGENTS.md" })?.id
            ?? agentDocuments.first?.id
        backups = []
    }
}

@MainActor
final class InstructionAppDelegate: NSObject, NSApplicationDelegate {
    weak var instructions: InstructionStore?
    weak var store: AppStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if store?.isMutating == true || store?.isPreparingChange == true {
            store?.libraryMessage = "파일 변경을 마친 뒤 종료할 수 있습니다."
            return .terminateCancel
        }
        store?.cancelSkillsCLIInstall()
        guard instructions?.hasDrafts == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "저장하지 않은 지침 초안이 있습니다"
        alert.informativeText = "취소하면 초안을 계속 편집하고 변경을 검토할 수 있습니다. 종료하면 저장하지 않은 초안은 사라집니다."
        alert.addButton(withTitle: "종료 취소")
        alert.addButton(withTitle: "저장하지 않고 종료")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
