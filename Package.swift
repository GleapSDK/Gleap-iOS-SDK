// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Gleap",
    platforms: [.iOS(.v9)],
    products: [
        .library(
            name: "Gleap",
            targets: ["Gleap"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
    ],
    targets: [
        .target(
           name: "Gleap",
           dependencies: [],
           path: "Sources/ObjCSources/",
           publicHeadersPath: ".",
           cSettings: [
              .headerSearchPath("Internal"),
           ]
        ),
        .testTarget(
            name: "GleapTests",
            dependencies: ["Gleap"]),
    ]
)
