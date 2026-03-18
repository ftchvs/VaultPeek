// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PlaidBar",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "PlaidBar", targets: ["PlaidBar"]),
        .executable(name: "PlaidBarServer", targets: ["PlaidBarServer"]),
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

        // MARK: - PlaidBarCore (Shared Library)
        .target(
            name: "PlaidBarCore",
            path: "Sources/PlaidBarCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // MARK: - Tests
        .testTarget(
            name: "PlaidBarTests",
            dependencies: ["PlaidBarCore"],
            path: "Tests/PlaidBarTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PlaidBarServerTests",
            dependencies: ["PlaidBarCore"],
            path: "Tests/PlaidBarServerTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PlaidBarCoreTests",
            dependencies: ["PlaidBarCore"],
            path: "Tests/PlaidBarCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
