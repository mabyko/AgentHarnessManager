// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SkillCore",
    platforms: [.macOS(.v26)],
    products: [.library(name: "SkillCore", targets: ["SkillCore"])],
    targets: [
        .target(name: "SkillCore"),
        .testTarget(name: "SkillCoreTests", dependencies: ["SkillCore"])
    ]
)
