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
            name: "libdatachannel",
            path: "Binaries/libdatachannel.artifactbundle"
        ),
        
        // Swift façade ------------------------------------
        .target(
            name: "AlloDataChannel",
            dependencies: ["libdatachannel"],
            path: "Sources/AlloWebRTC",
        ),
        
        .testTarget(
            name: "AlloDataChannelTest",
            dependencies: ["AlloDataChannel"],
            path: "Tests/AlloDataChannel",
        )
    ],
)
