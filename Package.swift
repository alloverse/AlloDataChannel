// swift-tools-version:6.0
import PackageDescription

let opensslPrefix = "/opt/homebrew/opt/openssl@3"

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
                /* 1. library search path */
                .unsafeFlags(["-L\(opensslPrefix)/lib"]),

                /* 2. link the two dylibs */
                .linkedLibrary("ssl",),
                .linkedLibrary("crypto"),
                .linkedLibrary("c++"),

                /* 3. make dyld find them at run-time */
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "\(opensslPrefix)/lib"
                ])
            ]

        ),
        
        .testTarget(
            name: "AlloDataChannelTest",
            dependencies: ["AlloDataChannel"],
            path: "Tests/AlloDataChannelTest",
        )
    ],
)
