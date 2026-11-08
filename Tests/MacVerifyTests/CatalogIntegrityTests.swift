// Tests/MacVerifyTests/CatalogIntegrityTests.swift
//
// 基线表本身也要被检查：它一旦出错，后面所有「原装性」判断都是错的，
// 而且错得很安静——不报错，只是给出一个看起来煞有介事但事实错误的结论。
//
// 这些用例与 Scripts/check_baseline.py 作用重叠是故意的：
// 脚本用在提交前和 CI，用例让 `swift test` 一条命令就能发现问题。
import XCTest
@testable import MacVerifyCore

final class CatalogIntegrityTests: XCTestCase {

    override func setUp() {
        super.setUp()
        forceEnglish()
    }

    func testNoDuplicateIdentifiersAcrossSpecs() {
        var seen = Set<String>()
        for spec in ModelSpecCatalog.specs {
            for identifier in spec.identifiers {
                XCTAssertFalse(seen.contains(identifier),
                               "\(identifier) 出现在多条基线条目里，后写入的会静默覆盖前一条")
                seen.insert(identifier)
            }
        }
    }

    func testEverySpecHasIdentifiersAndName() {
        for spec in ModelSpecCatalog.specs {
            XCTAssertFalse(spec.identifiers.isEmpty, "存在没有标识符的基线条目")
            XCTAssertFalse(spec.name.isEmpty)
            XCTAssertTrue(spec.name.contains("MacBook"), "名称不符合官方写法：\(spec.name)")
        }
    }

    func testEverySourceIsAnAppleSupportPage() {
        for spec in ModelSpecCatalog.specs {
            XCTAssertTrue(spec.source.hasPrefix("https://support.apple.com/"),
                          "\(spec.name) 的来源不是 Apple 支持页：\(spec.source)")
        }
    }

    func testDisplaySpecsArePlausible() {
        for spec in ModelSpecCatalog.specs {
            XCTAssertTrue((10.0...18.0).contains(spec.displayInches),
                          "\(spec.name) 对角线 \(spec.displayInches)″ 不合理")
            XCTAssertGreaterThan(spec.nativeWidth, 0)
            XCTAssertGreaterThan(spec.nativeHeight, 0)
            XCTAssertGreaterThan(spec.nativeWidth, spec.nativeHeight,
                                 "\(spec.name) 的分辨率应为横屏（宽 > 高）")
            // 面板像素密度：Retina 约 220–260 ppi，非 Retina（如 2015 Air 的 1440×900）约 110–130 ppi。
            // 越界说明分辨率与对角线这两个数抄错了一个。
            let diagonalPx = (Double(spec.nativeWidth * spec.nativeWidth + spec.nativeHeight * spec.nativeHeight)).squareRoot()
            let ppi = diagonalPx / spec.displayInches
            XCTAssertTrue((100.0...300.0).contains(ppi),
                          "\(spec.name) 像素密度 \(Int(ppi)) ppi 不合理，分辨率与尺寸可能不匹配")
        }
    }

    func testBatteryFiguresAreNotInverted() {
        for spec in ModelSpecCatalog.specs {
            XCTAssertGreaterThan(spec.batteryRatedWh, 0, "\(spec.name) 电池容量缺失")
            XCTAssertLessThan(spec.batteryRatedWh, 120, "\(spec.name) 电池容量超出笔记本范围")
            XCTAssertGreaterThanOrEqual(spec.batteryActualWh, 0)
            // 脚注的「实际额定」不会大于页面标注值
            XCTAssertLessThanOrEqual(spec.batteryActualWh, spec.batteryRatedWh,
                                     "\(spec.name) 的实际额定容量大于标注容量")
        }
    }

    func testOptionListsAreSortedAndUnique() {
        for spec in ModelSpecCatalog.specs {
            XCTAssertFalse(spec.memoryOptionsGB.isEmpty, "\(spec.name) 没有内存档位")
            XCTAssertEqual(spec.memoryOptionsGB, spec.memoryOptionsGB.sorted(),
                           "\(spec.name) 内存档位未排序")
            XCTAssertEqual(spec.memoryOptionsGB.count, Set(spec.memoryOptionsGB).count,
                           "\(spec.name) 内存档位有重复")

            XCTAssertFalse(spec.storageOptionsGB.isEmpty, "\(spec.name) 没有存储档位")
            XCTAssertEqual(spec.storageOptionsGB, spec.storageOptionsGB.sorted(),
                           "\(spec.name) 存储档位未排序")
            XCTAssertEqual(spec.storageOptionsGB.count, Set(spec.storageOptionsGB).count,
                           "\(spec.name) 存储档位有重复")

            XCTAssertEqual(spec.gpuCores, spec.gpuCores.sorted(), "\(spec.name) GPU 核心数未排序")
            XCTAssertEqual(spec.gpuCores.count, Set(spec.gpuCores).count,
                           "\(spec.name) GPU 核心数有重复")
        }
    }

    func testAdjacentStorageOptionsCannotOverlap() {
        // 匹配窗口是 [标称×0.93, 标称×1.02]。相邻档位至少差 2 倍，窗口绝不会互相覆盖，
        // 否则 256GB 的盘可能被认成 512GB 档。
        for spec in ModelSpecCatalog.specs {
            let options = spec.storageOptionsGB.sorted()
            for (lower, upper) in zip(options, options.dropFirst()) {
                XCTAssertGreaterThan(Double(upper) * 0.93, Double(lower) * 1.02,
                                     "\(spec.name) 的 \(lower)/\(upper) 档位匹配窗口重叠")
            }
        }
    }

    func testEveryBaselineIdentifierCanBeNamed() {
        // 有基线却没有机型名，界面会出现「规格基线：…」配「未收录的机型」的矛盾
        for spec in ModelSpecCatalog.specs {
            for identifier in spec.identifiers {
                XCTAssertNotNil(MacModelCatalog.entry(for: identifier),
                                "\(identifier) 有规格基线但机型表里没有名称")
            }
        }
    }

    func testModelCatalogHasNoDuplicateIdentifiers() {
        let identifiers = MacModelCatalog.entries.map(\.identifier)
        XCTAssertEqual(identifiers.count, Set(identifiers).count)
    }

    func testModelNumbersUseAppleFormat() {
        // 机壳型号一律 A + 4 位数字，写错会让用户对不上机身底部的印字
        for entry in MacModelCatalog.entries {
            guard let number = entry.modelNumber else { continue }
            XCTAssertTrue(number.range(of: "^A[0-9]{4}$", options: .regularExpression) != nil,
                          "\(entry.identifier) 的机壳型号格式不对：\(number)")
        }
    }

    func testUnlistedModelIsReportedAsUnlisted() {
        // 看名字就知道是 MacBook 但标识符不在表里 → 明确写「未收录」，不猜尺寸年份
        let name = MacModelCatalog.fallbackName(for: "MacBookPro99,9")
        XCTAssertTrue(name.lowercased().contains("unlisted") || name.contains("未收录"),
                      "实际为：\(name)")
        XCTAssertNil(MacModelCatalog.imageName(for: "MacBookPro99,9"), "未收录机型不应借用近似外形图")
    }

    func testNonMacIdentifierIsPassedThrough() {
        // 完全不认识的标识符原样返回，不硬套「MacBook」标签
        XCTAssertEqual(MacModelCatalog.fallbackName(for: "Mac99,9"), "Mac99,9")
    }

    func testCoverageCountsMatchTheTable() {
        let identifiers = Set(ModelSpecCatalog.specs.flatMap(\.identifiers))
        XCTAssertEqual(ModelSpecCatalog.identifierCount, identifiers.count)
        XCTAssertEqual(ModelSpecCatalog.familyCount, ModelSpecCatalog.specs.count)
    }
}
