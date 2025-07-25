// swift-tools-version:6.0
import PackageDescription

#if os(macOS)
let datachannelTarget: Target = .binaryTarget(
    name: "datachannel",
    path: "Binaries/datachannel.xcframework"
)
#else
let datachannelTarget: Target = .systemLibrary(
    name: "datachannel",
    path: "Binaries/datachannel.xcframework/macos-arm64/Headers",
    providers: [
        .aptItem(["libdatachannel-dev"])
    ],
)
#endif

let package = Package(
    name: "AlloDataChannel",
    platforms: [.macOS(.v13)],   // Linux implicit
    
    products: [
        .library(name: "AlloDataChannel", targets: ["AlloDataChannel"])
    ],
    
    dependencies: [
        // So we can use Combine on Linux.
        .package(url: "https://github.com/OpenCombine/OpenCombine.git", from: "0.14.0")
    ],
    
    targets: [
        // Binary artefacts ---------------------------------------------------
        datachannelTarget,

        // Swift façade ------------------------------------
        .target(
            name: "AlloDataChannel",
            dependencies: [
                "datachannel",
                // The shim uses Combine on Apple platforms and OpenCombine on linux
                .product(name: "OpenCombineShim", package: "opencombine"),
            ],
            path: "Sources/AlloDataChannel",
            linkerSettings: [
                .linkedLibrary("c++",    .when(platforms: [.macOS])),
                .linkedLibrary("stdc++", .when(platforms: [.linux])),
                .linkedLibrary("datachannel", .when(platforms: [.linux])),
            ],
        ),
        
        .testTarget(
            name: "AlloDataChannelTest",
            dependencies: ["AlloDataChannel"],
            path: "Tests/AlloDataChannelTest",
        )
    ],
)
