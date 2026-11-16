// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ComicStructure",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "ComicStructure", targets: ["ComicStructure"])],
    targets: [
        .target(name: "ComicStructure"),
        .testTarget(name: "ComicStructureTests", dependencies: ["ComicStructure"]),
    ]
)
