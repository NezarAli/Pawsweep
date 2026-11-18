// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MolePup",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Pinned: 1.99.2 and later do not compile with Swift 6.2 (PowerlineRenderer.swift).
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.1"),
    ],
    targets: [
        // Reads Mole's screen: its key hints and the selected row. No AppKit, so it is testable.
        .target(name: "MolePupCore", path: "Sources/MolePupCore"),
        .executableTarget(
            name: "MolePup",
            dependencies: ["MolePupCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Sources/MolePup"
        ),
        .testTarget(name: "MolePupCoreTests", dependencies: ["MolePupCore"], path: "Tests/MolePupCoreTests"),
    ]
)
