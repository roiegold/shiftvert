// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Shiftvert",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "Shiftvert", path: "Sources/Shiftvert")],
    swiftLanguageModes: [.v5]
)
