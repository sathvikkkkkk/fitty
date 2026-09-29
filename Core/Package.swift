// swift-tools-version:5.9
// Macht die plattformneutrale Core-Schicht als Bibliothek `FittrCore`
// verfügbar – genutzt vom Self-Test-Paket (../SelfTest). Die iOS-App bindet
// dieselben Quellen direkt über project.yml (xcodegen) ein und ignoriert
// dieses Manifest.
import PackageDescription

let package = Package(
    name: "FittrCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "FittrCore", targets: ["FittrCore"]),
    ],
    targets: [
        .target(
            name: "FittrCore",
            path: ".",
            exclude: ["Package.swift"]
        ),
    ]
)
