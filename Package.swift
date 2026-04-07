// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Kinetic",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Kinetic", targets: ["Kinetic"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Kinetic",
            path: "Kinetic"
        ),
        .testTarget(
            name: "KineticTests",
            dependencies: ["Kinetic"],
            path: "KineticTests"
        ),
    ]
)
