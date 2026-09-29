// swift-tools-version:5.9
// Dev-only: Verifiziert die Core-Logik ohne Xcode/iOS-SDK.
//   cd SelfTest && swift run fittr-selftest
import PackageDescription

let package = Package(
    name: "FittrSelfTest",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(path: "../Core"),
    ],
    targets: [
        .executableTarget(
            name: "fittr-selftest",
            dependencies: [
                .product(name: "FittrCore", package: "Core"),
            ]
        ),
    ]
)
