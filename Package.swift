// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AlloDataChannel",
    
    platforms: [.macOS(.v13)],   // Linux implicit
    
    products: [
        .library(name: "AlloDataChannel", targets: ["AlloDataChannel"])
    ],
    
    targets: [
        // Binary artefacts ---------------------------------------------------
        .binaryTarget(
            name: "datachannel",
            path: "Binaries/datachannel.xcframework"
        ),
        
        // Swift façade ------------------------------------
        .target(
            name: "AlloDataChannel",
            dependencies: ["datachannel"],
            path: "Sources/AlloDataChannel",
            linkerSettings: [
                .linkedLibrary("c++")
            ],
        ),
        
        .testTarget(
            name: "AlloDataChannelTest",
            dependencies: ["AlloDataChannel"],
            path: "Tests/AlloDataChannelTest",
        )
    ],
)
