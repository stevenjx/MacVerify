// Models/ModelSpecCatalog.swift
//
// 机型规格基线，用于判断「屏幕 / 内存 / 存储 / 电池是否是该机型应有的规格」。
//
// 收录规则（务必遵守，否则这张表本身就是新的假数据源）：
//   1. 每条必须能追溯到 Apple 官方技术规格页，`source` 写清链接；
//   2. 数值一律照抄官方页面，不做换算、不做四舍五入推测；
//   3. 电池同时记录「标注容量」与官方脚注的「实际额定容量」，比对用后者；
//   4. 只收录已核对过的机型。未收录的机型在界面上显示「无对照数据」，不做任何判断；
//   5. 用可选项表达差异：Intel 机型多为独立显卡、部分机型硬盘可自行更换，
//      这些字段留空 / 置 false 表示"该项不适用"，而不是"数据缺失"。
//
// 扩展方式见 docs/DEVELOPMENT_PLAN.md 的 B 系列任务。新增前必须先用官方页面核对，
// 不允许凭记忆或第三方数据填入。
import Foundation

struct ModelSpec {
    /// 共享同一份规格的机型标识（同一世代的不同芯片/配置变体）
    let identifiers: [String]
    let name: String

    let displayInches: Double
    let nativeWidth: Int
    let nativeHeight: Int

    /// Apple 页面标注的电池容量（Wh）
    let batteryRatedWh: Double
    /// Apple 页面脚注给出的实际额定容量（Wh）；官方未单独给出时等于标注值
    let batteryActualWh: Double

    /// 官方可选内存档位（GB）。这些机型的内存均为板载，不在档位内即异常。
    let memoryOptionsGB: [Int]
    /// 官方可选存储档位（十进制 GB：512GB SSD ≈ 500，1TB ≈ 1000）
    let storageOptionsGB: [Int]
    /// 官方可选 GPU 核心数。Intel 机型为独立显卡，核心数与机型无关，留空。
    let gpuCores: [Int]
    /// 存储是否板载。2016–2017 的 MacBook Pro 与 2017 MacBook Air 可自行更换硬盘，
    /// 这类机型容量不符属于正常，不做判断。
    let storageSoldered: Bool

    let source: String

    init(identifiers: [String], name: String,
         displayInches: Double, nativeWidth: Int, nativeHeight: Int,
         batteryRatedWh: Double, batteryActualWh: Double? = nil,
         memoryOptionsGB: [Int], storageOptionsGB: [Int],
         gpuCores: [Int] = [], storageSoldered: Bool = true,
         source: String) {
        self.identifiers = identifiers
        self.name = name
        self.displayInches = displayInches
        self.nativeWidth = nativeWidth
        self.nativeHeight = nativeHeight
        self.batteryRatedWh = batteryRatedWh
        self.batteryActualWh = batteryActualWh ?? batteryRatedWh
        self.memoryOptionsGB = memoryOptionsGB
        self.storageOptionsGB = storageOptionsGB
        self.gpuCores = gpuCores
        self.storageSoldered = storageSoldered
        self.source = source
    }
}

enum ModelSpecCatalog {

    /// 已逐条对照 Apple 官方技术规格页核对过的机型。
    private static let specs: [ModelSpec] = [
        // MARK: - Intel MacBook Pro
        ModelSpec(
            identifiers: ["MacBookPro15,1", "MacBookPro15,3"],
            name: "MacBook Pro (15-inch, 2018/2019)",
            displayInches: 15.4, nativeWidth: 2880, nativeHeight: 1800,
            batteryRatedWh: 83.6,
            memoryOptionsGB: [16, 32],
            storageOptionsGB: [251, 500, 1000, 2000, 4000],
            source: "https://support.apple.com/en-us/111949"
        ),
        ModelSpec(
            identifiers: ["MacBookPro16,1", "MacBookPro16,4"],
            name: "MacBook Pro (16-inch, 2019)",
            displayInches: 16.0, nativeWidth: 3072, nativeHeight: 1920,
            batteryRatedWh: 100, batteryActualWh: 99.8,
            memoryOptionsGB: [16, 32, 64],
            storageOptionsGB: [500, 1000, 2000, 4000, 8000],
            source: "https://support.apple.com/en-us/111932"
        ),

        // MARK: - Apple Silicon MacBook Air
        ModelSpec(
            identifiers: ["MacBookAir10,1"],
            name: "MacBook Air (M1, 2020)",
            displayInches: 13.3, nativeWidth: 2560, nativeHeight: 1600,
            batteryRatedWh: 49.9,
            memoryOptionsGB: [8, 16],
            storageOptionsGB: [121, 251, 500, 1000, 2000],
            gpuCores: [7, 8],
            source: "https://support.apple.com/en-us/111883"
        ),
        ModelSpec(
            identifiers: ["Mac14,2"],
            name: "MacBook Air (M2, 2022)",
            displayInches: 13.6, nativeWidth: 2560, nativeHeight: 1664,
            batteryRatedWh: 52.6,
            memoryOptionsGB: [8, 16, 24],
            storageOptionsGB: [251, 500, 1000, 2000],
            gpuCores: [8, 10],
            source: "https://support.apple.com/en-us/111867"
        ),

        // MARK: - Apple Silicon MacBook Pro
        ModelSpec(
            identifiers: ["MacBookPro18,3", "MacBookPro18,4"],
            name: "MacBook Pro (14-inch, 2021)",
            displayInches: 14.2, nativeWidth: 3024, nativeHeight: 1964,
            batteryRatedWh: 70, batteryActualWh: 69.6,
            memoryOptionsGB: [16, 32, 64],
            storageOptionsGB: [500, 1000, 2000, 4000, 8000],
            gpuCores: [14, 16, 24, 32],
            source: "https://support.apple.com/en-us/111902"
        ),
        ModelSpec(
            identifiers: ["MacBookPro18,1", "MacBookPro18,2"],
            name: "MacBook Pro (16-inch, 2021)",
            displayInches: 16.2, nativeWidth: 3456, nativeHeight: 2234,
            batteryRatedWh: 100, batteryActualWh: 99.6,
            memoryOptionsGB: [16, 32, 64],
            storageOptionsGB: [500, 1000, 2000, 4000, 8000],
            gpuCores: [16, 24, 32],
            source: "https://support.apple.com/en-us/111901"
        ),
        ModelSpec(
            identifiers: ["Mac14,5", "Mac14,9"],
            name: "MacBook Pro (14-inch, 2023)",
            displayInches: 14.2, nativeWidth: 3024, nativeHeight: 1964,
            batteryRatedWh: 70, batteryActualWh: 69.6,
            memoryOptionsGB: [16, 32, 64, 96],
            storageOptionsGB: [500, 1000, 2000, 4000, 8000],
            gpuCores: [16, 19, 30, 38],
            source: "https://support.apple.com/en-us/111340"
        ),
        ModelSpec(
            identifiers: ["Mac14,6", "Mac14,10"],
            name: "MacBook Pro (16-inch, 2023)",
            displayInches: 16.2, nativeWidth: 3456, nativeHeight: 2234,
            batteryRatedWh: 100, batteryActualWh: 99.6,
            memoryOptionsGB: [16, 32, 64, 96],
            storageOptionsGB: [500, 1000, 2000, 4000, 8000],
            gpuCores: [19, 30, 38],
            source: "https://support.apple.com/en-us/111838"
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

    /// 已收录的机型系列数（一个系列可能包含多个标识符）
    static var familyCount: Int { specs.count }

    /// 已收录的机型标识符总数
    static var identifierCount: Int { index.count }

    /// 供界面上做覆盖率提示
    static var coverageText: String {
        T("已收录 \(familyCount) 个机型系列 / \(identifierCount) 个标识符",
          "\(familyCount) model families / \(identifierCount) identifiers on file")
    }
}
