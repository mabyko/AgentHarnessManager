// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SkillCore",
    platforms: [.macOS(.v26)],
    products: [.library(name: "SkillCore", targets: ["SkillCore"]),
               .executable(name: "ahm", targets: ["AgentHarnessCLI"])],
    targets: [
        .target(name: "SkillCore"),
        .executableTarget(name: "AgentHarnessCLI", dependencies: ["SkillCore"]),
        .testTarget(name: "SkillCoreTests", dependencies: ["SkillCore"])
    ]
)
