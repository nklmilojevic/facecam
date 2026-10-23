// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Facecam",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FacecamKit", targets: ["FacecamKit"]),
        .executable(name: "facecam", targets: ["facecam"]),
        .executable(name: "FacecamBar", targets: ["FacecamBar"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "CFacecamUSB",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .target(name: "FacecamKit", dependencies: ["CFacecamUSB"]),
        .executableTarget(
            name: "facecam",
            dependencies: [
                "FacecamKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(name: "FacecamBar", dependencies: ["FacecamKit"]),
        .testTarget(name: "FacecamKitTests", dependencies: ["FacecamKit"]),
    ]
)
