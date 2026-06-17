// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DigitalPat",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.0.0")
    ],
    targets: [
        .executableTarget(
            name: "DigitalPat",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Supabase", package: "supabase-swift")
            ],
            path: "Sources/DigitalPat"
        )
    ]
)
