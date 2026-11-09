// Models/RegionCatalog.swift
//
// 销售区域识别。Apple 的配置编号（Part Number，如 Z17G000NALL/A）末尾字母表示销售地区：
// LL → 美国、CH → 中国大陆、ZP → 中国香港/澳门、ZA → 新加坡/马来西亚……
//
// Apple 不公开这张对照表，所以这里只收录能找到多方一致证据的代码。
// 认不出来就返回 nil，由界面写「未知」，绝不按前缀或机型年份猜。
import Foundation

struct SalesRegion {
    /// 地区代码，如 "LL"。界面上显示为 LL/A
    let code: String
    /// 地区名，如「美国版」
    let name: String
}

enum RegionCatalog {

    /// 两字母代码。这是现在最常见的形态（ZP/A、LL/A、CH/A）。
    private static let twoLetterCodes: Set<String> = [
        "LL", "CH", "ZP", "ZA", "TH", "KH", "TA", "AB", "RS", "GR", "IP", "PP", "ZD"
    ]

    /// 单字母代码。老机型上出现过 MF839D/A、MXVV2X/A 这种一位后缀。
    private static let oneLetterCodes: Set<String> = ["D", "B", "C", "J", "X"]

    /// 从配置编号解析销售区域。格式不对或代码未收录时返回 nil。
    static func region(forPartNumber partNumber: String) -> SalesRegion? {
        guard let code = codeSegment(partNumber) else { return nil }

        // 先两字母（…NALL → LL），再退到单字母（…839D → D）。顺序不能反。
        if code.count >= 2 {
            let two = String(code.suffix(2))
            if twoLetterCodes.contains(two) {
                return SalesRegion(code: two, name: name(for: two))
            }
        }

        // 单字母要求前面一位是数字：MF839D、MJLT2B、Z0Y3000D 都符合；
        // Apple 文档里的占位符是 MQRJ3xx/A（xx 为通配），结尾是字母 x，不能当成澳版。
        let one = String(code.suffix(1))
        if oneLetterCodes.contains(one), code.count >= 3,
           code[code.index(code.endIndex, offsetBy: -2)].isNumber {
            return SalesRegion(code: one, name: name(for: one))
        }
        return nil
    }

    /// 未收录时返回后缀，供界面提示「未知（后缀 DN）」
    static func unknownSuffix(forPartNumber partNumber: String) -> String? {
        guard let code = codeSegment(partNumber) else { return nil }
        return String(code.suffix(2))
    }

    /// 去掉结尾的 "/A" 得到代码段；不是 Apple 配置编号的格式就返回 nil。
    private static func codeSegment(_ partNumber: String) -> String? {
        let trimmed = partNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.hasSuffix("/A") else { return nil }
        let code = String(trimmed.dropLast(2))
        return code.isEmpty ? nil : code
    }

    /// 地区名走本地化函数，切换语言后立即生效。
    private static func name(for code: String) -> String {
        switch code {
        case "LL": return T("美国版", "United States")
        case "CH": return T("中国大陆版", "China mainland")
        case "ZP": return T("中国香港/澳门版", "Hong Kong / Macao")
        case "ZA": return T("新加坡/马来西亚版", "Singapore / Malaysia")
        case "TH": return T("泰国版", "Thailand")
        case "KH": return T("韩国版", "South Korea")
        case "TA": return T("中国台湾版", "Taiwan")
        case "AB": return T("阿联酋版", "United Arab Emirates")
        case "RS": return T("俄罗斯版", "Russia")
        case "GR": return T("希腊版", "Greece")
        case "IP": return T("意大利版", "Italy")
        case "PP": return T("菲律宾版", "Philippines")
        case "ZD", "D": return T("德国版", "Germany")
        case "B": return T("英国版", "United Kingdom")
        case "C": return T("加拿大版", "Canada")
        case "J": return T("日本版", "Japan")
        case "X": return T("澳大利亚/新西兰版", "Australia / New Zealand")
        default: return code
        }
    }
}
