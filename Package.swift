// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Wyspa",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Wyspa", targets: ["WyspaApp"]),
        .executable(name: "wyspa-hook", targets: ["WyspaHook"]),
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
        .target(name: "WyspaNotifications", dependencies: ["WyspaCore", "WyspaUI"], path: "Sources/Features/Notifications"),
        // Protokół hooka: tylko Foundation, żeby `wyspa-hook` startował szybko.
        .target(name: "WyspaHookKit", path: "Sources/WyspaHookKit"),
        .executableTarget(name: "WyspaHook", dependencies: ["WyspaHookKit"], path: "Sources/WyspaHook"),
        .target(name: "WyspaClaudeMonitor", dependencies: ["WyspaCore", "WyspaUI", "WyspaHookKit"], path: "Sources/Features/ClaudeMonitor"),
        .target(name: "WyspaTimer", dependencies: ["WyspaCore", "WyspaUI"], path: "Sources/Features/Timer"),
        .target(name: "WyspaNotes", dependencies: ["WyspaCore", "WyspaUI"], path: "Sources/Features/Notes"),
        .target(name: "WyspaClipboard", dependencies: ["WyspaCore", "WyspaUI"], path: "Sources/Features/Clipboard"),
        .target(name: "WyspaShortcuts", dependencies: ["WyspaCore", "WyspaUI"], path: "Sources/Features/Shortcuts"),
        .target(name: "WyspaMirror", dependencies: ["WyspaCore", "WyspaUI"], path: "Sources/Features/Mirror"),
        .target(name: "WyspaCalendar", dependencies: ["WyspaCore", "WyspaUI"], path: "Sources/Features/Calendar"),
        .target(name: "WyspaReminders", dependencies: ["WyspaCore", "WyspaUI"], path: "Sources/Features/Reminders"),
        .target(
            name: "WyspaFeatures",
            dependencies: [
                "WyspaCore", "WyspaUI", "WyspaMedia", "WyspaShelf", "WyspaHUD", "WyspaPower", "WyspaBluetooth",
                "WyspaTimer", "WyspaNotes", "WyspaNotifications", "WyspaClaudeMonitor", "WyspaClipboard", "WyspaShortcuts", "WyspaMirror", "WyspaCalendar", "WyspaReminders",
            ],
            path: "Sources/Features/Catalog"
        ),
        .executableTarget(
            name: "WyspaApp",
            dependencies: ["WyspaCore", "WyspaUI", "WyspaFeatures", "WyspaNotifications"],
            path: "Sources/WyspaApp"
        ),
        .testTarget(name: "WyspaCoreTests", dependencies: ["WyspaCore"], path: "Tests/WyspaCoreTests"),
        .testTarget(name: "WyspaUITests", dependencies: ["WyspaCore", "WyspaUI"], path: "Tests/WyspaUITests"),
        .testTarget(name: "WyspaMediaTests", dependencies: ["WyspaMedia"], path: "Tests/WyspaMediaTests"),
        .testTarget(name: "WyspaShelfTests", dependencies: ["WyspaShelf"], path: "Tests/WyspaShelfTests"),
        .testTarget(name: "WyspaHUDTests", dependencies: ["WyspaHUD"], path: "Tests/WyspaHUDTests"),
        .testTarget(name: "WyspaPowerTests", dependencies: ["WyspaPower"], path: "Tests/WyspaPowerTests"),
        .testTarget(name: "WyspaTimerTests", dependencies: ["WyspaTimer"], path: "Tests/WyspaTimerTests"),
        .testTarget(name: "WyspaNotesTests", dependencies: ["WyspaNotes"], path: "Tests/WyspaNotesTests"),
        .testTarget(name: "WyspaClipboardTests", dependencies: ["WyspaClipboard"], path: "Tests/WyspaClipboardTests"),
        .testTarget(name: "WyspaShortcutsTests", dependencies: ["WyspaShortcuts"], path: "Tests/WyspaShortcutsTests"),
        .testTarget(name: "WyspaCalendarTests", dependencies: ["WyspaCalendar"], path: "Tests/WyspaCalendarTests"),
        .testTarget(name: "WyspaRemindersTests", dependencies: ["WyspaReminders"], path: "Tests/WyspaRemindersTests"),
        .testTarget(name: "WyspaClaudeMonitorTests", dependencies: ["WyspaClaudeMonitor", "WyspaHookKit"], path: "Tests/WyspaClaudeMonitorTests"),
        .testTarget(name: "WyspaNotificationsTests", dependencies: ["WyspaNotifications"], path: "Tests/WyspaNotificationsTests"),
        .testTarget(name: "WyspaBluetoothTests", dependencies: ["WyspaBluetooth"], path: "Tests/WyspaBluetoothTests"),
    ]
)
