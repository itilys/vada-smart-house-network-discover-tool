// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VaDaNetworkDiscover",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "NetworkDiscoveryCore",
            targets: ["NetworkDiscoveryCore"]
        ),
        .executable(
            name: "NetworkDiscoverApp",
            targets: ["NetworkDiscoverApp"]
        ),
        .executable(
            name: "netdiscover",
            targets: ["netdiscover"]
        )
    ],
    targets: [
        .target(
            name: "NetworkDiscoveryCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "NetworkDiscoverApp",
            dependencies: ["NetworkDiscoveryCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "netdiscover",
            dependencies: ["NetworkDiscoveryCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "NetworkDiscoveryCoreTests",
            dependencies: ["NetworkDiscoveryCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
