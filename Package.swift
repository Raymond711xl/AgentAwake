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
        .library(
            name: "AgentAwakeSetupCore",
            targets: ["AgentAwakeSetupCore"]
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
                .linkedFramework("IOKit"),
                .linkedFramework("CoreServices")
            ]
        ),
        .executableTarget(
            name: "AgentAwake",
            dependencies: ["AgentAwakeCore", "AgentAwakeSetupCore"],
            linkerSettings: [
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "AgentAwakeHook",
            dependencies: ["AgentAwakeCore"]
        ),
        .executableTarget(
            name: "AgentAwakeHookSetup",
            dependencies: ["AgentAwakeSetupCore"]
        ),
        .target(
            name: "AgentAwakeSetupCore"
        ),
        .executableTarget(
            name: "AgentAwakeSelfTest",
            dependencies: ["AgentAwakeCore", "AgentAwakeSetupCore"]
        ),
        .executableTarget(
            name: "AgentAwakePowerProbe",
            dependencies: ["AgentAwakeCore"]
        )
    ],
    swiftLanguageModes: [.v5]
)
