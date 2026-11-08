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
    /// 官方可选 GPU 核心数。Intel 机型为集成/独立显卡，核心数与机型标识无关，留空。
    let gpuCores: [Int]
    /// 存储判断策略：
    ///   true   —— 板载焊接，容量必须落在官方档位；
    ///   false  —— 可自行更换，容量差异属正常，不做判断；
    ///   nil    —— 同一世代内既有可更换也有板载焊接的形态，仅凭系统信息无法区分，不做判断。
    let storageSoldered: Bool?

    let source: String

    init(identifiers: [String], name: String,
         displayInches: Double, nativeWidth: Int, nativeHeight: Int,
         batteryRatedWh: Double, batteryActualWh: Double? = nil,
         memoryOptionsGB: [Int], storageOptionsGB: [Int],
         gpuCores: [Int] = [], storageSoldered: Bool? = true,
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
    /// 同一标识符若对应多个年代且规格不同，取并集（更宽松，不会误报），并在 name 中注明年份。
    private static let specs: [ModelSpec] = [
        // MARK: - Intel MacBook Air
        // MacBookAir7,2 同时是「13-inch, 2017」与「13-inch, Early 2015」，
        // 两者都是 13.3″/1440×900/54Wh/128–512GB，仅内存档位不同（2017 只有 8GB，2015 有 4GB 或 8GB），
        // 系统无法区分二者，因此内存取并集。
        ModelSpec(
            identifiers: ["MacBookAir7,2"],
            name: "MacBook Air (13-inch, 2015/2017)",
            displayInches: 13.3, nativeWidth: 1440, nativeHeight: 900,
            batteryRatedWh: 54,
            memoryOptionsGB: [4, 8],
            storageOptionsGB: [128, 256, 512],
            storageSoldered: nil,
            source: "https://support.apple.com/en-us/111924 · https://support.apple.com/en-us/111956"
        ),
        ModelSpec(
            identifiers: ["MacBookAir8,1"],
            name: "MacBook Air (Retina, 13-inch, 2018)",
            displayInches: 13.3, nativeWidth: 2560, nativeHeight: 1600,
            batteryRatedWh: 50.3,
            memoryOptionsGB: [8, 16],
            storageOptionsGB: [128, 256, 512, 1500],
            source: "https://support.apple.com/en-us/111933"
        ),
        ModelSpec(
            identifiers: ["MacBookAir8,2"],
            name: "MacBook Air (Retina, 13-inch, 2019)",
            displayInches: 13.3, nativeWidth: 2560, nativeHeight: 1600,
            batteryRatedWh: 49.9,
            memoryOptionsGB: [8, 16],
            storageOptionsGB: [128, 256, 512, 1000],
            source: "https://support.apple.com/en-us/111948"
        ),
        ModelSpec(
            identifiers: ["MacBookAir9,1"],
            name: "MacBook Air (Retina, 13-inch, 2020)",
            displayInches: 13.3, nativeWidth: 2560, nativeHeight: 1600,
            batteryRatedWh: 49.9,
            memoryOptionsGB: [8, 16],
            storageOptionsGB: [256, 512, 1000, 2000],
            source: "https://support.apple.com/en-us/111991"
        ),

        // MARK: - Intel MacBook Pro 13-inch 2016–2017
        // 这几代的硬盘形态在同年份的不同配置间不一致（部分型号为可更换模块，部分为板载焊接），
        // Apple 技术规格页不说明这一点，因此 storageSoldered 置 nil，不做容量判断。
        ModelSpec(
            identifiers: ["MacBookPro13,1"],
            name: "MacBook Pro (13-inch, 2016, Two Thunderbolt 3 ports)",
            displayInches: 13.3, nativeWidth: 2560, nativeHeight: 1600,
            batteryRatedWh: 54.5,
            memoryOptionsGB: [8, 16],
            storageOptionsGB: [256, 512, 1000],
            storageSoldered: nil,
            source: "https://support.apple.com/en-us/111999"
        ),
        ModelSpec(
            identifiers: ["MacBookPro13,2"],
            name: "MacBook Pro (13-inch, 2016, Four Thunderbolt 3 ports)",
            displayInches: 13.3, nativeWidth: 2560, nativeHeight: 1600,
            batteryRatedWh: 49.2,
            memoryOptionsGB: [8, 16],
            storageOptionsGB: [256, 512, 1000],
            storageSoldered: nil,
            source: "https://support.apple.com/en-us/112003"
        ),
        ModelSpec(
            identifiers: ["MacBookPro14,1"],
            name: "MacBook Pro (13-inch, 2017, Two Thunderbolt 3 ports)",
            displayInches: 13.3, nativeWidth: 2560, nativeHeight: 1600,
            batteryRatedWh: 54.5,
            memoryOptionsGB: [8, 16],
            storageOptionsGB: [128, 256, 512, 1000],
            storageSoldered: nil,
            source: "https://support.apple.com/en-us/111951"
        ),
        ModelSpec(
            identifiers: ["MacBookPro14,2"],
            name: "MacBook Pro (13-inch, 2017, Four Thunderbolt 3 ports)",
            displayInches: 13.3, nativeWidth: 2560, nativeHeight: 1600,
            batteryRatedWh: 49.2,
            memoryOptionsGB: [8, 16],
            storageOptionsGB: [256, 512, 1000],
            storageSoldered: nil,
            source: "https://support.apple.com/en-us/111972"
        ),

        // MARK: - Intel MacBook Pro 15-inch 2016–2017
        ModelSpec(
            identifiers: ["MacBookPro13,3"],
            name: "MacBook Pro (15-inch, 2016)",
            displayInches: 15.4, nativeWidth: 2880, nativeHeight: 1800,
            batteryRatedWh: 76.0,
            memoryOptionsGB: [16],
            storageOptionsGB: [256, 512, 1000, 2000],
            storageSoldered: nil,
            source: "https://support.apple.com/en-us/111975"
        ),
        ModelSpec(
            identifiers: ["MacBookPro14,3"],
            name: "MacBook Pro (15-inch, 2017)",
            displayInches: 15.4, nativeWidth: 2880, nativeHeight: 1800,
            batteryRatedWh: 76.0,
            memoryOptionsGB: [16],
            storageOptionsGB: [256, 512, 1000, 2000],
            storageSoldered: nil,
            source: "https://support.apple.com/en-us/111947"
        ),

        // MARK: - Intel MacBook Pro 13-inch 2018–2020
        // MacBookPro15,2 同时是「13-inch, 2018, Four TB3」与「13-inch, 2019, Four TB3」，
        // 两代规格一致（58.0Wh / 8–16GB / 256GB–2TB），合并为一条。
        ModelSpec(
            identifiers: ["MacBookPro15,2"],
            name: "MacBook Pro (13-inch, 2018/2019, Four Thunderbolt 3 ports)",
            displayInches: 13.3, nativeWidth: 2560, nativeHeight: 1600,
            batteryRatedWh: 58.0,
            memoryOptionsGB: [8, 16],
            storageOptionsGB: [256, 512, 1000, 2000],
            source: "https://support.apple.com/en-us/111925 · https://support.apple.com/en-us/111997"
        ),
        ModelSpec(
            identifiers: ["MacBookPro15,4"],
            name: "MacBook Pro (13-inch, 2019, Two Thunderbolt 3 ports)",
            displayInches: 13.3, nativeWidth: 2560, nativeHeight: 1600,
            batteryRatedWh: 58.2,
            memoryOptionsGB: [8, 16],
            storageOptionsGB: [128, 256, 512, 1000, 2000],
            source: "https://support.apple.com/en-us/111945"
        ),
        ModelSpec(
            identifiers: ["MacBookPro16,2"],
            name: "MacBook Pro (13-inch, 2020, Four Thunderbolt 3 ports)",
            displayInches: 13.3, nativeWidth: 2560, nativeHeight: 1600,
            batteryRatedWh: 58.0,
            memoryOptionsGB: [16, 32],
            storageOptionsGB: [512, 1000, 2000, 4000],
            source: "https://support.apple.com/en-us/111339"
        ),
        ModelSpec(
            identifiers: ["MacBookPro16,3"],
            name: "MacBook Pro (13-inch, 2020, Two Thunderbolt 3 ports)",
            displayInches: 13.3, nativeWidth: 2560, nativeHeight: 1600,
            batteryRatedWh: 58.2,
            memoryOptionsGB: [8, 16],
            storageOptionsGB: [256, 512, 1000, 2000],
            source: "https://support.apple.com/en-us/111981"
        ),

        // MARK: - Intel MacBook Pro 15-inch 2018–2019
        ModelSpec(
            identifiers: ["MacBookPro15,1", "MacBookPro15,3"],
            name: "MacBook Pro (15-inch, 2018/2019)",
            displayInches: 15.4, nativeWidth: 2880, nativeHeight: 1800,
            batteryRatedWh: 83.6,
            memoryOptionsGB: [16, 32],
            storageOptionsGB: [256, 512, 1000, 2000, 4000],
            source: "https://support.apple.com/en-us/111949"
        ),
        ModelSpec(
            identifiers: ["MacBookPro16,1", "MacBookPro16,4"],
            name: "MacBook Pro (16-inch, 2019)",
            displayInches: 16.0, nativeWidth: 3072, nativeHeight: 1920,
            batteryRatedWh: 100, batteryActualWh: 99.8,
            memoryOptionsGB: [16, 32, 64],
            storageOptionsGB: [512, 1000, 2000, 4000, 8000],
            source: "https://support.apple.com/en-us/111932"
        ),

        // MARK: - Apple Silicon MacBook Air
        ModelSpec(
            identifiers: ["MacBookAir10,1"],
            name: "MacBook Air (M1, 2020)",
            displayInches: 13.3, nativeWidth: 2560, nativeHeight: 1600,
            batteryRatedWh: 49.9,
            memoryOptionsGB: [8, 16],
            storageOptionsGB: [128, 256, 512, 1000, 2000],
            gpuCores: [7, 8],
            source: "https://support.apple.com/en-us/111883"
        ),
        ModelSpec(
            identifiers: ["Mac14,2"],
            name: "MacBook Air (M2, 2022)",
            displayInches: 13.6, nativeWidth: 2560, nativeHeight: 1664,
            batteryRatedWh: 52.6,
            memoryOptionsGB: [8, 16, 24],
            storageOptionsGB: [256, 512, 1000, 2000],
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
            storageOptionsGB: [512, 1000, 2000, 4000, 8000],
            gpuCores: [14, 16, 24, 32],
            source: "https://support.apple.com/en-us/111902"
        ),
        ModelSpec(
            identifiers: ["MacBookPro18,1", "MacBookPro18,2"],
            name: "MacBook Pro (16-inch, 2021)",
            displayInches: 16.2, nativeWidth: 3456, nativeHeight: 2234,
            batteryRatedWh: 100, batteryActualWh: 99.6,
            memoryOptionsGB: [16, 32, 64],
            storageOptionsGB: [512, 1000, 2000, 4000, 8000],
            gpuCores: [16, 24, 32],
            source: "https://support.apple.com/en-us/111901"
        ),
        ModelSpec(
            identifiers: ["Mac14,5", "Mac14,9"],
            name: "MacBook Pro (14-inch, 2023)",
            displayInches: 14.2, nativeWidth: 3024, nativeHeight: 1964,
            batteryRatedWh: 70, batteryActualWh: 69.6,
            memoryOptionsGB: [16, 32, 64, 96],
            storageOptionsGB: [512, 1000, 2000, 4000, 8000],
            gpuCores: [16, 19, 30, 38],
            source: "https://support.apple.com/en-us/111340"
        ),
        ModelSpec(
            identifiers: ["Mac14,6", "Mac14,10"],
            name: "MacBook Pro (16-inch, 2023)",
            displayInches: 16.2, nativeWidth: 3456, nativeHeight: 2234,
            batteryRatedWh: 100, batteryActualWh: 99.6,
            memoryOptionsGB: [16, 32, 64, 96],
            storageOptionsGB: [512, 1000, 2000, 4000, 8000],
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
