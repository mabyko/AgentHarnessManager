import SkillCore
import SwiftUI

struct AgentIcon: View {
    let agent: SkillAgent
    var size: CGFloat = 18

    var body: some View {
        Group {
            if agent == .custom {
                Image(systemName: "terminal")
            } else {
                Image("Agent-" + agent.rawValue)
                    .renderingMode(agent == .pi ? .template : .original)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
