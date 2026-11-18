// swift-tools-version: 5.9
let package = Package(
    name: "MyAwesomeApp",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "MyAwesomeApp",
            targets: ["MyAwesomeApp"]
        ),
    ],
    targets: [
        .target(
            name: "MyAwesomeApp",
            dependencies: []
        ),
    ]
)
// func testName() {
//     statements
// }