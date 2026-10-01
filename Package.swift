// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Wyspa",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Wyspa", targets: ["WyspaApp"]),
    ],
    targets: [
        .target(name: "WyspaCore", path: "Sources/WyspaCore"),
        .target(name: "WyspaUI", dependencies: ["WyspaCore"], path: "Sources/WyspaUI"),
        // Katalog modułów. Każdy moduł funkcji to osobny target w Sources/Features/<Nazwa>.
        .target(name: "WyspaFeatures", dependencies: ["WyspaCore", "WyspaUI"], path: "Sources/Features/Catalog"),
        .executableTarget(
            name: "WyspaApp",
            dependencies: ["WyspaCore", "WyspaUI", "WyspaFeatures"],
            path: "Sources/WyspaApp"
        ),
        .testTarget(name: "WyspaCoreTests", dependencies: ["WyspaCore"], path: "Tests/WyspaCoreTests"),
    ]
)
