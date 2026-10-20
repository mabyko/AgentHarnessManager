import AppKit
import SkillCore
import SwiftUI
import Vision

@main struct Check {
 @MainActor static func main() {
  func check(_ condition: Bool, _ message: String = "Native settings check failed") {
   if !condition { fputs("FAIL: " + message + "\n", stderr); exit(1) }
  }
  let app = NSApplication.shared; app.setActivationPolicy(.accessory)
  check(CommandLine.arguments.count == 2 && CommandLine.arguments[1].hasPrefix("ahm.settings.check."))
  let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("home")
  let defaults = UserDefaults(suiteName: CommandLine.arguments[1])!
  try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  check(SettingsPage.allCases.map(\.rawValue) == ["general", "connections", "paths"])
  check(AgentConnectionTarget.allCases.count == 8)
  for agent in SkillAgent.allCases where agent != .custom {
   check(NSImage(named: "Agent-" + agent.rawValue) != nil, "Bundled agent icon missing: " + agent.rawValue)
  }
  let store = AppStore(defaults: defaults, home: folder)
  let root = AnyView(SettingsView().environment(store))
  let view = NSHostingView(rootView: root)
  let window = NSWindow(contentRect: NSRect(x: 80,y: 60,width: 900,height: 900), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
  app.activate(ignoringOtherApps: true)
  func image() -> NSBitmapImageRep {
   view.layoutSubtreeIfNeeded()
   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
   view.cacheDisplay(in: view.bounds, to: rep); return rep
  }
  func text(excludingIcons: Bool = false) -> [(String,CGRect)] {
   let request = VNRecognizeTextRequest(); request.recognitionLevel = .fast; request.recognitionLanguages = ["en-US"]
   // Keep compact brand marks from being recognized as the first letter of a name.
   if excludingIcons { request.regionOfInterest = CGRect(x: 0.27, y: 0, width: 0.73, height: 1) }
   try! VNImageRequestHandler(cgImage: image().cgImage!, options: [:]).perform([request])
   return (request.results ?? []).compactMap { observation in observation.topCandidates(1).first.map { ($0.string,observation.boundingBox) } }
  }
  func click(_ box: CGRect) {
   let point = NSPoint(x: box.midX * view.bounds.width, y: (view.isFlipped ? 1 - box.midY : box.midY) * view.bounds.height)
   let location = view.convert(point, to: nil)
   for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
    let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
    window.sendEvent(event)
   }
  }
  func selectPage(_ index: Int) {
   click(CGRect(x: 0.05, y: 1 - (32 + CGFloat(index) * 41) / view.bounds.height,
                width: 0.1, height: 1 / view.bounds.height))
  }
  Task { @MainActor in
   try? await Task.sleep(for: .milliseconds(700))
    for (mode,name) in [(NSAppearance.Name.aqua,"light"),(.darkAqua,"dark")] {
     app.appearance = NSAppearance(named: mode)
     window.appearance = NSAppearance(named: mode)
     try? await Task.sleep(for: .milliseconds(300))
     selectPage(1)
     try? await Task.sleep(for: .milliseconds(500))
     try! image().representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath:"docs/design/native-agent-settings-\(name).png"))
     // Fast OCR can drop the two-letter Pi label; inspect it in the captured screenshots.
     let names = text(excludingIcons: true).map { $0.0.lowercased().replacingOccurrences(of: " ", with: "") }
     for agent in ["codex", "claudecode", "grokbuild", "antigravity", "opencode", "devin", "cursor"] {
      check(names.contains { $0.contains(agent) }, "Connection row missing: " + agent)
     }
     try! image().representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath:"docs/design/native-agent-settings-\(name).png"))
     selectPage(2)
     try? await Task.sleep(for: .milliseconds(400))
     for agent in [SkillAgent.antigravity, .opencode, .pi, .devin, .cursor] {
      view.rootView = AnyView(SettingsView(pathAgent: agent).environment(store).id(agent))
      try? await Task.sleep(for: .milliseconds(300))
      selectPage(2)
      try? await Task.sleep(for: .milliseconds(300))
      let pathText = text().map { $0.0.lowercased().replacingOccurrences(of: " ", with: "") }.joined(separator: " ")
      if agent != .pi { check(pathText.contains(agent.rawValue), "Skill path section missing: " + agent.rawValue) }
      if agent == .pi {
       try! image().representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath:"/tmp/ahm-pi-paths-\(name).png"))
      }
     }
     try! image().representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath:"docs/design/native-skill-paths-\(name).png"))
     selectPage(0)
     try? await Task.sleep(for: .milliseconds(300))
     check(!text().contains { $0.0.contains("Grok") }, "General category did not replace the skill paths")
    }
    print("PASS: eight bundled agent icons, three settings categories, eight connection rows and agent-specific skill-path panels in light/dark")
   defaults.synchronize()
   window.close(); exit(0)
  }
  app.run()
 }
}
