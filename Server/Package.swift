// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SlamServer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Packages/SlamCore"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.28.0"),
    ],
    targets: [
        .executableTarget(name: "slam", dependencies: [
            "SlamServer", "HevyImport", .product(name: "SlamCore", package: "SlamCore"),
        ]),
        .target(name: "SlamServer", dependencies: [
            .product(name: "SlamCore", package: "SlamCore"),
            .product(name: "Hummingbird", package: "hummingbird"),
        ]),
        .target(name: "HevyImport", dependencies: [.product(name: "SlamCore", package: "SlamCore")]),
        .testTarget(name: "SlamServerTests", dependencies: [
            "SlamServer",
            .product(name: "HummingbirdTesting", package: "hummingbird"),
        ]),
        .testTarget(name: "HevyImportTests", dependencies: ["HevyImport"]),
    ],
    swiftLanguageModes: [.v5]
)
