// Models/MacModelCatalog.swift
import Foundation

struct MacModelEntry {
    let identifier: String
    let name: String
    let image: String?
    let modelNumber: String?
}

enum MacModelCatalog {
    /// 机型表，名称采用 Apple 官方写法（MacBook Pro (14-inch, 2024) 这一格式）。
    ///
    /// 两条硬约束：
    /// 1. 不写芯片型号。同一个标识符常常对应多个芯片（如 Mac16,6 / Mac16,8 都是
    ///    M4 Pro 或 M4 Max），标识符无法唯一确定，写死就会出错。芯片由硬件实时读取。
    /// 2. 只收录 Apple 官方支持文档列出的标识符。未收录的机型如实显示"未收录"，
    ///    不按前缀猜尺寸或年份——那对二手验机是误导。
    private static let entries: [MacModelEntry] = [
        // MacBook Air — Intel
        .init(identifier: "MacBookAir5,1", name: "MacBook Air (11-inch, Mid 2012)", image: "macbook_air_mid_2012", modelNumber: "A1465"),
        .init(identifier: "MacBookAir5,2", name: "MacBook Air (13-inch, Mid 2012)", image: "macbook_air_mid_2012", modelNumber: "A1466"),
        .init(identifier: "MacBookAir6,1", name: "MacBook Air (11-inch, 2013/2014)", image: "macbook_air_mid_2012", modelNumber: "A1465"),
        .init(identifier: "MacBookAir6,2", name: "MacBook Air (13-inch, 2013/2014)", image: "macbook_air_mid_2012", modelNumber: "A1466"),
        .init(identifier: "MacBookAir7,1", name: "MacBook Air (11-inch, Early 2015)", image: "macbook_air_2017_image", modelNumber: "A1465"),
        .init(identifier: "MacBookAir7,2", name: "MacBook Air (13-inch, 2015/2017)", image: "macbook_air_2017_image", modelNumber: "A1466"),
        .init(identifier: "MacBookAir8,1", name: "MacBook Air (Retina, 13-inch, 2018)", image: "macbook_air_2018_image", modelNumber: "A1932"),
        .init(identifier: "MacBookAir8,2", name: "MacBook Air (Retina, 13-inch, 2019)", image: "macbook_air_2018_image", modelNumber: "A1932"),
        .init(identifier: "MacBookAir9,1", name: "MacBook Air (Retina, 13-inch, 2020)", image: "macbook_air_2018_image", modelNumber: "A2179"),
        // MacBook Air — Apple Silicon
        .init(identifier: "MacBookAir10,1", name: "MacBook Air (M1, 2020)", image: "macbook_air_m1_2020", modelNumber: "A2337"),
        .init(identifier: "Mac14,2", name: "MacBook Air (M2, 2022)", image: "macbook_air_m2_2022", modelNumber: "A2681"),
        .init(identifier: "Mac14,15", name: "MacBook Air (15-inch, M2, 2023)", image: "macbook_air_15_m2_2023", modelNumber: "A2941"),
        .init(identifier: "Mac15,12", name: "MacBook Air (13-inch, M3, 2024)", image: "macbook_air_13-inch_2024_hero", modelNumber: nil),
        .init(identifier: "Mac15,13", name: "MacBook Air (15-inch, M3, 2024)", image: "macbook_air_15-inch_2024_hero", modelNumber: nil),
        .init(identifier: "Mac16,12", name: "MacBook Air (13-inch, M4, 2025)", image: "macbook_air_13-inch_2025_hero", modelNumber: nil),
        .init(identifier: "Mac16,13", name: "MacBook Air (15-inch, M4, 2025)", image: "macbook_air_15-inch_2025_hero", modelNumber: nil),
        .init(identifier: "Mac17,3", name: "MacBook Air (13-inch, M5, 2026)", image: "macbook_air_13-inch_2026_hero", modelNumber: nil),
        .init(identifier: "Mac17,4", name: "MacBook Air (15-inch, M5, 2026)", image: "macbook_air_15-inch_2026_hero", modelNumber: nil),

        // MacBook Pro — Intel
        .init(identifier: "MacBookPro9,1", name: "MacBook Pro (15-inch, Mid 2012)", image: "mbp_15late2016_image", modelNumber: "A1286"),
        .init(identifier: "MacBookPro9,2", name: "MacBook Pro (13-inch, Mid 2012)", image: "mbp_13_2018_4ports_image", modelNumber: "A1278"),
        .init(identifier: "MacBookPro10,1", name: "MacBook Pro (Retina, 15-inch, 2012/2013)", image: "mbp_15late2016_image", modelNumber: "A1398"),
        .init(identifier: "MacBookPro10,2", name: "MacBook Pro (Retina, 13-inch, 2012/2013)", image: "mbp_13_2018_4ports_image", modelNumber: "A1425"),
        .init(identifier: "MacBookPro11,1", name: "MacBook Pro (Retina, 13-inch, 2013/2014)", image: "mbp_13_2018_4ports_image", modelNumber: "A1502"),
        .init(identifier: "MacBookPro11,2", name: "MacBook Pro (Retina, 15-inch, 2013)", image: "mbp_15late2016_image", modelNumber: "A1398"),
        .init(identifier: "MacBookPro11,3", name: "MacBook Pro (Retina, 15-inch, 2014)", image: "mbp_15late2016_image", modelNumber: "A1398"),
        .init(identifier: "MacBookPro11,4", name: "MacBook Pro (Retina, 15-inch, Mid 2015)", image: "mbp_15late2016_image", modelNumber: "A1398"),
        .init(identifier: "MacBookPro11,5", name: "MacBook Pro (Retina, 15-inch, Mid 2015, dGPU)", image: "mbp_15late2016_image", modelNumber: "A1398"),
        .init(identifier: "MacBookPro12,1", name: "MacBook Pro (Retina, 13-inch, Early 2015)", image: "mbp_13_2018_4ports_image", modelNumber: "A1502"),
        .init(identifier: "MacBookPro13,1", name: "MacBook Pro (13-inch, 2016, 2×TB3)", image: "mbp_15late2016_image", modelNumber: "A1708"),
        .init(identifier: "MacBookPro13,2", name: "MacBook Pro (13-inch, 2016, 4×TB3)", image: "mbp_15late2016_image", modelNumber: "A1706"),
        .init(identifier: "MacBookPro13,3", name: "MacBook Pro (15-inch, 2016)", image: "mbp_15late2016_image", modelNumber: "A1707"),
        .init(identifier: "MacBookPro14,1", name: "MacBook Pro (13-inch, 2017, 2×TB3)", image: "mbp_13_2018_4ports_image", modelNumber: "A1708"),
        .init(identifier: "MacBookPro14,2", name: "MacBook Pro (13-inch, 2017, 4×TB3)", image: "mbp_13_2018_4ports_image", modelNumber: "A1706"),
        .init(identifier: "MacBookPro14,3", name: "MacBook Pro (15-inch, 2017)", image: "mbp_15late2016_image", modelNumber: "A1707"),
        .init(identifier: "MacBookPro15,1", name: "MacBook Pro (15-inch, 2018/2019)", image: "mbp_15_2018_image", modelNumber: "A1990"),
        .init(identifier: "MacBookPro15,2", name: "MacBook Pro (13-inch, 2018/2019, 4×TB3)", image: "mbp_13_2018_4ports_image", modelNumber: "A1989"),
        .init(identifier: "MacBookPro15,3", name: "MacBook Pro (15-inch, 2019)", image: "mbp_15_2018_image", modelNumber: "A1990"),
        .init(identifier: "MacBookPro15,4", name: "MacBook Pro (13-inch, 2019, 2×TB3)", image: "mbp_13_2018_4ports_image", modelNumber: "A2159"),
        .init(identifier: "MacBookPro16,1", name: "MacBook Pro (16-inch, 2019)", image: "mbp_16_2019_image", modelNumber: "A2141"),
        .init(identifier: "MacBookPro16,2", name: "MacBook Pro (13-inch, 2020, 4×TB3)", image: "mbp_13_2020_image", modelNumber: "A2251"),
        .init(identifier: "MacBookPro16,3", name: "MacBook Pro (13-inch, 2020, 2×TB3)", image: "mbp_13_2020_image", modelNumber: "A2289"),
        .init(identifier: "MacBookPro16,4", name: "MacBook Pro (16-inch, 2019)", image: "mbp_16_2019_image", modelNumber: "A2141"),
        // MacBook Pro — Apple Silicon
        .init(identifier: "MacBookPro17,1", name: "MacBook Pro (13-inch, M1, 2020)", image: "mbp_13_m1_2020_image", modelNumber: "A2338"),
        .init(identifier: "MacBookPro18,1", name: "MacBook Pro (16-inch, 2021)", image: "mbp_16_2021_image", modelNumber: "A2485"),
        .init(identifier: "MacBookPro18,2", name: "MacBook Pro (16-inch, 2021)", image: "mbp_16_2021_image", modelNumber: "A2485"),
        .init(identifier: "MacBookPro18,3", name: "MacBook Pro (14-inch, 2021)", image: "mbp_14_2021_image", modelNumber: "A2442"),
        .init(identifier: "MacBookPro18,4", name: "MacBook Pro (14-inch, 2021)", image: "mbp_14_2021_image", modelNumber: "A2442"),
        .init(identifier: "Mac14,7", name: "MacBook Pro (13-inch, M2, 2022)", image: "mbp_13_m2_2022_image", modelNumber: "A2338"),
        .init(identifier: "Mac14,5", name: "MacBook Pro (14-inch, 2023)", image: "mbp_14_2023_image", modelNumber: "A2779"),
        .init(identifier: "Mac14,9", name: "MacBook Pro (14-inch, 2023)", image: "mbp_14_2023_image", modelNumber: "A2779"),
        .init(identifier: "Mac14,6", name: "MacBook Pro (16-inch, 2023)", image: "mbp_16_2023_image", modelNumber: "A2780"),
        .init(identifier: "Mac14,10", name: "MacBook Pro (16-inch, 2023)", image: "mbp_16_2023_image", modelNumber: "A2780"),
        .init(identifier: "Mac15,3", name: "MacBook Pro (14-inch, Nov 2023)", image: "mbp_14_nov2023_image", modelNumber: "A2918"),
        .init(identifier: "Mac15,6", name: "MacBook Pro (14-inch, Nov 2023)", image: "mbp_14_nov2023_image", modelNumber: "A2992"),
        .init(identifier: "Mac15,8", name: "MacBook Pro (14-inch, Nov 2023)", image: "mbp_14_nov2023_image", modelNumber: "A2992"),
        .init(identifier: "Mac15,10", name: "MacBook Pro (14-inch, Nov 2023)", image: "mbp_14_nov2023_image", modelNumber: "A2992"),
        .init(identifier: "Mac15,7", name: "MacBook Pro (16-inch, Nov 2023)", image: "mbp_16_nov2023_image", modelNumber: "A2991"),
        .init(identifier: "Mac15,9", name: "MacBook Pro (16-inch, Nov 2023)", image: "mbp_16_nov2023_image", modelNumber: "A2991"),
        .init(identifier: "Mac15,11", name: "MacBook Pro (16-inch, Nov 2023)", image: "mbp_16_nov2023_image", modelNumber: "A2991"),
        .init(identifier: "Mac16,1", name: "MacBook Pro (14-inch, 2024)", image: "mbp_14_2024_hero", modelNumber: nil),
        .init(identifier: "Mac16,6", name: "MacBook Pro (14-inch, 2024)", image: "mbp_14_2024_hero", modelNumber: nil),
        .init(identifier: "Mac16,8", name: "MacBook Pro (14-inch, 2024)", image: "mbp_14_2024_hero", modelNumber: nil),
        .init(identifier: "Mac16,5", name: "MacBook Pro (16-inch, 2024)", image: "mbp_16_2024_hero", modelNumber: nil),
        .init(identifier: "Mac16,7", name: "MacBook Pro (16-inch, 2024)", image: "mbp_16_2024_hero", modelNumber: nil),
        .init(identifier: "Mac17,2", name: "MacBook Pro (14-inch, M5, 2025)", image: "mbp_14_m5_hero", modelNumber: nil),
        .init(identifier: "Mac17,6", name: "MacBook Pro (16-inch, 2026)", image: "mbp_16_2026_hero", modelNumber: nil),
        .init(identifier: "Mac17,8", name: "MacBook Pro (16-inch, 2026)", image: "mbp_16_2026_hero", modelNumber: nil),
        .init(identifier: "Mac17,7", name: "MacBook Pro (14-inch, 2026)", image: "mbp_14_2026_hero", modelNumber: nil),
        .init(identifier: "Mac17,9", name: "MacBook Pro (14-inch, 2026)", image: "mbp_14_2026_hero", modelNumber: nil)
    ]

    private static let index: [String: MacModelEntry] = {
        var dictionary: [String: MacModelEntry] = [:]
        for entry in entries { dictionary[entry.identifier] = entry }
        return dictionary
    }()

    static func entry(for identifier: String) -> MacModelEntry? {
        index[identifier]
    }

    /// 未知机型：如实标注"未收录"，不按型号前缀猜尺寸或年份。
    /// 猜错机型对二手验机是误导，宁可显示未知。
    static func fallbackName(for identifier: String) -> String {
        let lower = identifier.lowercased()
        if lower.contains("macbookair") || lower.contains("macbookpro") || lower.contains("macbook") {
            return T("未收录的机型（\(identifier)）", "Unlisted model (\(identifier))")
        }
        return identifier
    }

    /// 未收录机型不返回外形图，避免用近似机型冒充
    static func imageName(for identifier: String) -> String? {
        entry(for: identifier)?.image
    }
}
