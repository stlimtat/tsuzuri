// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Archive",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "Archive", targets: ["Archive"])],
    targets: [
        .target(
            name: "CArchive",
            exclude: ["COPYING"],
            cSettings: [.define("HAVE_CONFIG_H"), .headerSearchPath(".")],
            linkerSettings: [.linkedLibrary("z")]
        ),
        .target(name: "Archive", dependencies: ["CArchive"]),
        .testTarget(name: "ArchiveTests", dependencies: ["Archive"]),
    ]
)
