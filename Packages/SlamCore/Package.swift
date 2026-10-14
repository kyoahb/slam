// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SlamCore",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [.library(name: "SlamCore", targets: ["SlamCore"])],
    targets: [
        .target(name: "SlamCore"),
        .testTarget(name: "SlamCoreTests", dependencies: ["SlamCore"]),
    ]
)
