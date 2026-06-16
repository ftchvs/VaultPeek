// swift-tools-version: 6.0

import Foundation
import PackageDescription

let selectedDeveloperLibraryPath = ProcessInfo.processInfo.environment["DEVELOPER_DIR"].map {
    "\($0)/Library/Developer/usr/lib"
}
let swiftTestingInteropLibraryPaths = ([
    selectedDeveloperLibraryPath,
    "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
    "/Applications/Xcode.app/Contents/Developer/Library/Developer/usr/lib",
    "/Applications/Xcode_16.app/Contents/Developer/Library/Developer/usr/lib",
] as [String?])
    .compactMap { $0 }
    .filter { FileManager.default.fileExists(atPath: "\($0)/lib_TestingInterop.dylib") }

let swiftTestingLinkerFlags = swiftTestingInteropLibraryPaths.flatMap { path in
    ["-L", path, "-Xlinker", "-rpath", "-Xlinker", path]
}

let swiftTestingTestDependency: Target.Dependency = .product(name: "Testing", package: "swift-testing")
let swiftTestingLinkerSettings: [LinkerSetting] = [.unsafeFlags(swiftTestingLinkerFlags)]

let package = Package(
    name: "PlaidBar",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "PlaidBar", targets: ["PlaidBar"]),
        .executable(name: "PlaidBarServer", targets: ["PlaidBarServer"]),
        .executable(name: "PlaidBarWidgetExtension", targets: ["PlaidBarWidgetExtension"]),
        .executable(name: "plaidbar-cli", targets: ["PlaidBarCLI"]),
        .library(name: "PlaidBarCore", targets: ["PlaidBarCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0"),
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.2.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess", from: "4.2.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-fluent", from: "2.0.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        // Keep SwiftPM resolution compatible with the documented Swift 6.0
        // baseline. async-http-client 1.34.0 dropped Package@swift-6.0.swift.
        .package(url: "https://github.com/swift-server/async-http-client.git", exact: "1.33.1"),
        // Keep `swift test` working on command-line toolchains that ship the
        // Swift Testing macro plugin but not the importable `Testing` module.
        .package(url: "https://github.com/swiftlang/swift-testing", exact: "6.1.3"),
    ],
    targets: [
        // MARK: - PlaidBar (macOS App)
        .executableTarget(
            name: "PlaidBar",
            dependencies: [
                "PlaidBarCore",
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess"),
                .product(name: "KeychainAccess", package: "KeychainAccess"),
            ],
            path: "Sources/PlaidBar",
            exclude: [
                "Resources/AppIcon.icns",
                "Resources/Info.plist",
                "Resources/PlaidBar.entitlements",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // MARK: - PlaidBar Widget Extension (WidgetKit/App Intents)
        .executableTarget(
            name: "PlaidBarWidgetExtension",
            dependencies: [
                "PlaidBarCore",
            ],
            path: "Sources/PlaidBarWidgetExtension",
            exclude: [
                "Resources/Info.plist",
                "Resources/PlaidBarWidgetExtension.entitlements",
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // MARK: - PlaidBarServer (Local Server)
        .executableTarget(
            name: "PlaidBarServer",
            dependencies: [
                "PlaidBarCore",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdFluent", package: "hummingbird-fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/PlaidBarServer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // MARK: - PlaidBar CLI (Local command-line client)
        .executableTarget(
            name: "PlaidBarCLI",
            dependencies: [
                "PlaidBarCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/PlaidBarCLI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // MARK: - PlaidBarCore (Shared Library)
        .target(
            name: "PlaidBarCore",
            path: "Sources/PlaidBarCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // MARK: - Tests
        .testTarget(
            name: "PlaidBarTests",
            dependencies: ["PlaidBarCore", swiftTestingTestDependency],
            path: "Tests/PlaidBarTests",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: swiftTestingLinkerSettings
        ),
        .testTarget(
            name: "PlaidBarServerTests",
            dependencies: [
                "PlaidBarCore",
                "PlaidBarServer",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
                swiftTestingTestDependency,
            ],
            path: "Tests/PlaidBarServerTests",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: swiftTestingLinkerSettings
        ),
        .testTarget(
            name: "PlaidBarCoreTests",
            dependencies: ["PlaidBarCore", swiftTestingTestDependency],
            path: "Tests/PlaidBarCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: swiftTestingLinkerSettings
        ),
    ]
)
