// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BridgeMark",
    defaultLocalization: "fr",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "BridgeMark",
            targets: ["BridgeMark"]
        )
    ],
    targets: [
        .executableTarget(
            name: "BridgeMark",
            path: "Sources/BridgeMark",
            exclude: ["Info.plist", "Localizable.xcstrings", "Assets.xcassets"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/BridgeMark/Info.plist",
                ])
            ]
        )
    ]
)
