// swift-tools-version:5.9
import PackageDescription

// Multi-device sync integration tests for Digital Pat's friend graph.
// Uses the EXACT supabase-swift version the app pins (2.47.1) so the realtime
// presence + postgres-changes + RPC code paths exercised here match production.
let package = Package(
    name: "PatSyncTests",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift", exact: "2.47.1"),
    ],
    targets: [
        .executableTarget(
            name: "PatSyncTests",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
            ]
        ),
    ]
)
