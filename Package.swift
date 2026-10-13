// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "atkctl",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "atkctl", targets: ["atkctl"]),
        .executable(name: "ATKBar", targets: ["ATKBar"]),
        .library(name: "ATKKit", targets: ["ATKKit"]),
    ],
    targets: [
        .target(name: "ATKKit", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "atkctl", dependencies: ["ATKKit"]),
        .executableTarget(name: "ATKBar", dependencies: ["ATKKit"]),
        .testTarget(name: "ATKKitTests", dependencies: ["ATKKit"]),
    ],
    swiftLanguageModes: [.v5]
)
