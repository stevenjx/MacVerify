// swift-tools-version:5.9
//
// 这个 Package.swift 只服务于测试与 CI，不参与 App 打包。
// App 本体仍由 MacVerify.xcodeproj 构建；这里把同一份源码编成模块，
// 让 `swift test` 能在命令行（以及 GitHub Actions 的 macOS runner）上跑。
//
// 排除 App/：那里有 @main，库目标不能带入口点。
import PackageDescription

let package = Package(
    name: "MacVerify",
    platforms: [.macOS(.v12)],
    targets: [
        .target(
            name: "MacVerifyCore",
            path: "MacVerify",
            exclude: ["App", "Assets.xcassets", "Resources"]
        ),
        .testTarget(
            name: "MacVerifyTests",
            dependencies: ["MacVerifyCore"],
            path: "Tests/MacVerifyTests"
        )
    ]
)
