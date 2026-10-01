// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Gleap",
    platforms: [.iOS(.v15)],
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
           path: "Sources/",
           resources: [.copy("PrivacyInfo.xcprivacy")],
           // Only Sources/ObjCSources is public; Sources/Internal stays inside the SDK.
           publicHeadersPath: "ObjCSources",
           cSettings: [
              .headerSearchPath("Internal"),
           ],
           linkerSettings: [
              // gzip for the logs sent for capture requests.
              .linkedLibrary("z"),
           ]
        ),
        .testTarget(
            name: "GleapTests",
            dependencies: ["Gleap"]),
    ]
)
