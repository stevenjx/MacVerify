// Models/ModelSpecCatalog.swift
//
// 机型规格基线，用于判断「屏幕 / 内存 / 存储 / 电池是否是该机型应有的规格」。
//
// 收录规则（务必遵守，否则这张表本身就是新的假数据源）：
//   1. 每条必须能追溯到 Apple 官方技术规格页，`source` 写清链接；
//   2. 数值一律照抄官方页面，不做换算、不做四舍五入推测；
//   3. 电池同时记录「标注容量」与官方脚注的「实际额定容量」，比对用后者；
//   4. 只收录已核对过的机型。未收录的机型在界面上显示「无对照数据」，不做任何判断。
//
// 新增机型时请在真机上验证 displayInches / memory / storage 三项能被正确判定，
// 再补进本表。
import Foundation

struct ModelSpec {
    /// 共享同一份规格的机型标识（同一世代的不同芯片变体）
    let identifiers: [String]
    let name: String

    let displayInches: Double
    let nativeWidth: Int
    let nativeHeight: Int

    /// Apple 页面标注的电池容量（Wh）
    let batteryRatedWh: Double
    /// Apple 页面脚注给出的实际额定容量（Wh）
    let batteryActualWh: Double

    /// 官方可选内存档位（GB）
    let memoryOptionsGB: [Int]
    /// 官方可选存储档位（十进制 GB：512GB SSD ≈ 500，1TB ≈ 1000）
    let storageOptionsGB: [Int]
    /// 官方可选 GPU 核心数
    let gpuCores: [Int]

    let source: String
}

enum ModelSpecCatalog {

    private static let specs: [ModelSpec] = [
        ModelSpec(
            identifiers: ["Mac14,5", "Mac14,9"],
            name: "MacBook Pro (14-inch, 2023)",
            displayInches: 14.2,
            nativeWidth: 3024,
            nativeHeight: 1964,
            batteryRatedWh: 70,
            batteryActualWh: 69.6,
            memoryOptionsGB: [16, 32, 64, 96],
            storageOptionsGB: [500, 1000, 2000, 4000, 8000],
            gpuCores: [16, 19, 30, 38],
            source: "https://support.apple.com/en-us/111340"
        ),
        ModelSpec(
            identifiers: ["Mac14,6", "Mac14,10"],
            name: "MacBook Pro (16-inch, 2023)",
            displayInches: 16.2,
            nativeWidth: 3456,
            nativeHeight: 2234,
            batteryRatedWh: 100,
            batteryActualWh: 99.6,
            memoryOptionsGB: [16, 32, 64, 96],
            storageOptionsGB: [500, 1000, 2000, 4000, 8000],
            gpuCores: [19, 30, 38],
            source: "https://support.apple.com/en-us/111838"
        ),
        ModelSpec(
            identifiers: ["Mac14,2"],
            name: "MacBook Air (M2, 2022)",
            displayInches: 13.6,
            nativeWidth: 2560,
            nativeHeight: 1664,
            batteryRatedWh: 52.6,
            batteryActualWh: 52.6,
            memoryOptionsGB: [8, 16, 24],
            storageOptionsGB: [251, 500, 1000, 2000],
            gpuCores: [8, 10],
            source: "https://support.apple.com/en-us/111867"
        ),
        ModelSpec(
            identifiers: ["MacBookAir10,1"],
            name: "MacBook Air (M1, 2020)",
            displayInches: 13.3,
            nativeWidth: 2560,
            nativeHeight: 1600,
            batteryRatedWh: 49.9,
            batteryActualWh: 49.9,
            memoryOptionsGB: [8, 16],
            storageOptionsGB: [121, 251, 500, 1000, 2000],
            gpuCores: [7, 8],
            source: "https://support.apple.com/en-us/111883"
        )
    ]

    private static let index: [String: ModelSpec] = {
        var dictionary: [String: ModelSpec] = [:]
        for spec in specs {
            for identifier in spec.identifiers { dictionary[identifier] = spec }
        }
        return dictionary
    }()

    static func spec(for identifier: String) -> ModelSpec? {
        index[identifier]
    }

    static var entryCount: Int { specs.count }
}
