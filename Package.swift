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
        .target(name: "WyspaMedia", dependencies: ["WyspaCore", "WyspaUI"], path: "Sources/Features/Media"),
        .target(name: "WyspaShelf", dependencies: ["WyspaCore", "WyspaUI"], path: "Sources/Features/Shelf"),
        .target(name: "WyspaHUD", dependencies: ["WyspaCore", "WyspaUI"], path: "Sources/Features/HUD"),
        .target(name: "WyspaPower", dependencies: ["WyspaCore", "WyspaUI"], path: "Sources/Features/Power"),
        .target(name: "WyspaBluetooth", dependencies: ["WyspaCore", "WyspaUI"], path: "Sources/Features/Bluetooth"),
        .target(
            name: "WyspaFeatures",
            dependencies: [
                "WyspaCore", "WyspaUI", "WyspaMedia", "WyspaShelf", "WyspaHUD", "WyspaPower", "WyspaBluetooth",
            ],
            path: "Sources/Features/Catalog"
        ),
        .executableTarget(
            name: "WyspaApp",
            dependencies: ["WyspaCore", "WyspaUI", "WyspaFeatures"],
            path: "Sources/WyspaApp"
        ),
        .testTarget(name: "WyspaCoreTests", dependencies: ["WyspaCore"], path: "Tests/WyspaCoreTests"),
        .testTarget(name: "WyspaMediaTests", dependencies: ["WyspaMedia"], path: "Tests/WyspaMediaTests"),
        .testTarget(name: "WyspaShelfTests", dependencies: ["WyspaShelf"], path: "Tests/WyspaShelfTests"),
        .testTarget(name: "WyspaHUDTests", dependencies: ["WyspaHUD"], path: "Tests/WyspaHUDTests"),
        .testTarget(name: "WyspaPowerTests", dependencies: ["WyspaPower"], path: "Tests/WyspaPowerTests"),
        .testTarget(name: "WyspaBluetoothTests", dependencies: ["WyspaBluetooth"], path: "Tests/WyspaBluetoothTests"),
    ]
)
