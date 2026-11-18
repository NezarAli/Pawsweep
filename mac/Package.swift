// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pawsweep",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Pinned: 1.99.2 and later do not compile with Swift 6.2 (PowerlineRenderer.swift).
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.1"),
    ],
    targets: [
        // Reads Mole's screen: its key hints and the selected row. No AppKit, so it is testable.
        .target(name: "PawsweepCore", path: "Sources/PawsweepCore"),
        .executableTarget(
            name: "Pawsweep",
            dependencies: ["PawsweepCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Sources/Pawsweep"
        ),
        .testTarget(name: "PawsweepCoreTests", dependencies: ["PawsweepCore"], path: "Tests/PawsweepCoreTests"),
    ]
)
