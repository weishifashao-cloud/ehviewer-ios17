// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EhUI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "EhUI", targets: ["EhUI"]),
    ],
    dependencies: [
        .package(path: "../EhCore"),
        .package(path: "../EhNetwork"),
        .package(path: "../EhParser"),
        .package(path: "../EhSpider"),
        .package(path: "../EhDownload"),
        .package(url: "https://github.com/SDWebImage/SDWebImageSwiftUI.git", from: "3.1.0"),
    ],
    targets: [
        .target(
            name: "EhUI",
            dependencies: [
                .product(name: "EhModels", package: "EhCore"),
                .product(name: "EhDatabase", package: "EhCore"),
                .product(name: "EhSettings", package: "EhCore"),
                .product(name: "EhAPI", package: "EhNetwork"),
                .product(name: "EhCookie", package: "EhNetwork"),
                .product(name: "EhParser", package: "EhParser"),
                .product(name: "EhSpider", package: "EhSpider"),
                .product(name: "EhDownload", package: "EhDownload"),
                .product(name: "SDWebImageSwiftUI", package: "SDWebImageSwiftUI"),
            ],
            path: "Sources"
        ),
    ]
)
