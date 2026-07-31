// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgentAwake",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AgentAwakeCore",
            targets: ["AgentAwakeCore"]
        ),
        .executable(
            name: "AgentAwake",
            targets: ["AgentAwake"]
        ),
        .executable(
            name: "AgentAwakeHook",
            targets: ["AgentAwakeHook"]
        ),
        .executable(
            name: "AgentAwakeHookSetup",
            targets: ["AgentAwakeHookSetup"]
        )
    ],
    targets: [
        .target(
            name: "AgentAwakeCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "AgentAwake",
            dependencies: ["AgentAwakeCore"]
        ),
        .executableTarget(
            name: "AgentAwakeHook",
            dependencies: ["AgentAwakeCore"]
        ),
        .executableTarget(
            name: "AgentAwakeHookSetup"
        ),
        .executableTarget(
            name: "AgentAwakeSelfTest",
            dependencies: ["AgentAwakeCore"]
        ),
        .executableTarget(
            name: "AgentAwakePowerProbe",
            dependencies: ["AgentAwakeCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
