// Tests/MacVerifyTests/ReportAndHistoryTests.swift
//
// 覆盖「报告 → 快照 → 差异」这条链。
// 关键约束：快照必须由报告 JSON 生成，导出与对比共用一套键与格式，
// 否则导入另一台机器的报告时会冒出一堆假差异。
import XCTest
@testable import MacVerifyCore

final class ReportAndHistoryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        forceEnglish()
    }

    private func makeReportJSON(_ info: MacSystemInfo, battery: BatterySnapshot) -> Data {
        guard let data = ReportService.json(info: info, battery: battery) else {
            XCTFail("ReportService.json 返回 nil")
            return Data()
        }
        return data
    }

    // MARK: - 报告

    func testJSONIsStructurallyValid() throws {
        let info = makeInfo(panel: makePanel())
        let data = makeReportJSON(info, battery: makeBattery(voltage: 11.45))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(root["tool"] as? String, "MacVerify")
        XCTAssertNotNil(root["version"] as? String)
        XCTAssertNotNil(root["scanned_at"] as? String)
        XCTAssertNotNil(root["fingerprint"] as? String)
        XCTAssertNotNil(root["verdict"] as? String)

        let sections = try XCTUnwrap(root["sections"] as? [String: Any])
        XCTAssertGreaterThanOrEqual(sections.count, 5)
    }

    func testMissingValuesAreNullNotZero() throws {
        // 缺失即不可用：JSON 里必须是 null / unavailable，不能用 0 顶替
        var info = makeInfo(panel: nil)
        info.modelFromSysctl = nil
        var battery = makeBattery(design: 0, rawMax: 0)
        battery.cycleCountAvailable = false
        battery.designCycleCountAvailable = false
        let data = makeReportJSON(info, battery: battery)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let sections = try XCTUnwrap(root["sections"] as? [String: Any])

        var unavailable = 0
        for (_, items) in sections {
            guard let items = items as? [String: Any] else { continue }
            for (_, raw) in items {
                guard let item = raw as? [String: Any] else { continue }
                if item["state"] as? String == "unavailable" {
                    unavailable += 1
                    // 不可用项要么没有 value，要么明确写 unavailable，不能是 "0"
                    if let value = item["value"] as? String {
                        XCTAssertNotEqual(value, "0", "\(item["label"] ?? "?") 用 0 顶替了缺失值")
                    }
                }
            }
        }
        XCTAssertGreaterThan(unavailable, 0, "该用例应当产生若干不可用项")
    }

    func testVerdictCountsMismatch() {
        // 干净机：一致性全绿
        let clean = makeInfo(panel: makePanel())
        let cleanIssues = ReportService.build(info: clean, battery: makeBattery(voltage: 11.45)).issues

        // 篡改机：系统报告机型与内核不一致
        var tampered = makeInfo(panel: makePanel())
        tampered.modelIdentifier = "Mac15,3"
        let tamperedReport = ReportService.build(info: tampered, battery: makeBattery(voltage: 11.45))

        XCTAssertGreaterThan(tamperedReport.issues, cleanIssues)
        XCTAssertTrue(tamperedReport.verdict.lowercased().contains("mismatch"),
                      "结论应说明存在不一致，实际为：\(tamperedReport.verdict)")
    }

    func testUnavailableIsNotCountedAsIssue() {
        // 电池额定电压取不到时该项为「不可用」，不能计入问题数
        let withVoltage = makeInfo(panel: makePanel())
        let a = ReportService.build(info: withVoltage, battery: makeBattery(voltage: 11.45)).issues
        let b = ReportService.build(info: withVoltage, battery: makeBattery(voltage: nil)).issues
        XCTAssertEqual(a, b)
    }

    func testMarkdownCarriesFingerprintAndVerdict() {
        let info = makeInfo(panel: makePanel())
        let battery = makeBattery(voltage: 11.45)
        let markdown = ReportService.markdown(info: info, battery: battery)
        let fingerprint = ReportService.fingerprint(of: ReportService.build(info: info, battery: battery).sections)

        XCTAssertTrue(markdown.contains("MacVerify"))
        XCTAssertTrue(markdown.contains(DeviceFingerprint.display(fingerprint)))
        XCTAssertTrue(markdown.contains("Mac14,9"))
        XCTAssertGreaterThan(markdown.split(separator: "\n").count, 30)
    }

    // MARK: - 快照

    func testSnapshotRoundTripsFromReport() throws {
        let info = makeInfo(panel: makePanel())
        let battery = makeBattery(voltage: 11.45)
        let data = makeReportJSON(info, battery: battery)
        let snapshot = try XCTUnwrap(ScanSnapshot.make(reportJSON: data, source: "test.json"))

        XCTAssertEqual(snapshot.serialNumber, "KVNY9P2061")
        XCTAssertFalse(snapshot.fields.isEmpty)
        XCTAssertFalse(snapshot.fields.contains { $0.label.isEmpty })

        let byKey = Dictionary(uniqueKeysWithValues: snapshot.fields.map { ($0.key, $0.value) })
        XCTAssertEqual(byKey["model_identifier"], "Mac14,9")
        XCTAssertEqual(byKey["memory"], "16 GB")
        XCTAssertEqual(byKey["storage_capacity"], "1TB")
        XCTAssertEqual(snapshot.fingerprintMatches, true)
    }

    func testSnapshotRejectsForeignJSON() {
        let notOurs = #"{"hello": 1}"#.data(using: .utf8)!
        XCTAssertNil(ScanSnapshot.make(reportJSON: notOurs, source: "x"))
        XCTAssertNil(ScanSnapshot.make(reportJSON: Data("not json".utf8), source: "x"))
    }

    func testTamperingOneIdentityFieldBreaksFingerprint() throws {
        let data = makeReportJSON(makeInfo(panel: makePanel()), battery: makeBattery(voltage: 11.45))
        let snapshot = try XCTUnwrap(ScanSnapshot.make(reportJSON: data, source: "test.json"))

        var forged = snapshot
        forged.fields = snapshot.fields.map { field in
            field.key == "serial_number"
                ? SnapshotField(key: field.key, label: field.label, value: "ZZZ9999999")
                : field
        }
        XCTAssertEqual(forged.fingerprintMatches, false)
    }

    func testLegacyReportWithoutFingerprintReportsNil() throws {
        let data = makeReportJSON(makeInfo(panel: makePanel()), battery: makeBattery(voltage: 11.45))
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        root.removeValue(forKey: "fingerprint")
        let stripped = try JSONSerialization.data(withJSONObject: root)

        let snapshot = try XCTUnwrap(ScanSnapshot.make(reportJSON: stripped, source: "legacy.json"))
        XCTAssertNil(snapshot.fingerprintMatches, "旧报告没有指纹，应为 nil 而不是 false")
    }

    // MARK: - 差异

    func testDiffCountsOnlyChangedFields() throws {
        let a = try XCTUnwrap(ScanSnapshot.make(
            reportJSON: makeReportJSON(makeInfo(memoryGB: 16, panel: makePanel()), battery: makeBattery()),
            source: "a"))
        let b = try XCTUnwrap(ScanSnapshot.make(
            reportJSON: makeReportJSON(makeInfo(memoryGB: 32, panel: makePanel()), battery: makeBattery()),
            source: "b"))

        let rows = SnapshotDiff.compare(a, b)
        XCTAssertEqual(rows.count, a.fields.count)
        XCTAssertEqual(SnapshotDiff.changedCount(rows), 1)

        let memory = try XCTUnwrap(rows.first { $0.key == "memory" })
        XCTAssertTrue(memory.changed)
        XCTAssertEqual(memory.before, "16 GB")
        XCTAssertEqual(memory.after, "32 GB")
    }

    func testDiffOfIdenticalSnapshotsIsEmpty() throws {
        let data = makeReportJSON(makeInfo(panel: makePanel()), battery: makeBattery())
        let a = try XCTUnwrap(ScanSnapshot.make(reportJSON: data, source: "a"))
        let b = try XCTUnwrap(ScanSnapshot.make(reportJSON: data, source: "b"))
        XCTAssertEqual(SnapshotDiff.changedCount(SnapshotDiff.compare(a, b)), 0)
    }

    // MARK: - 落盘

    func testHistoryDeduplicatesDriftingFields() {
        let store = makeIsolatedDefaults()
        ScanHistoryStore.clear(store)

        // 同一台机器再扫一次，电池循环与健康度会变，但硬件状态没变
        let first = ScanSnapshot.make(info: makeInfo(panel: makePanel()),
                                      battery: makeBattery(rawMax: 5441), source: "run1")
        let second = ScanSnapshot.make(info: makeInfo(panel: makePanel()),
                                       battery: makeBattery(rawMax: 5438), source: "run2")
        ScanHistoryStore.append(first, to: store)
        ScanHistoryStore.append(second, to: store)

        XCTAssertEqual(ScanHistoryStore.load(from: store).count, 1, "漂移字段不应造成重复快照")
        XCTAssertEqual(ScanHistoryStore.load(from: store).first?.source, "run2", "应保留最新一份")
    }

    func testHistoryKeepsDifferentMachines() {
        let store = makeIsolatedDefaults()
        ScanHistoryStore.clear(store)

        var other = makeInfo(panel: makePanel())
        other.serialNumber = "C02YYYYYYYY"
        other.serialFromIOKit = "C02YYYYYYYY"

        ScanHistoryStore.append(ScanSnapshot.make(info: makeInfo(panel: makePanel()),
                                                 battery: makeBattery(), source: "machine-a"), to: store)
        ScanHistoryStore.append(ScanSnapshot.make(info: other, battery: makeBattery(), source: "machine-b"), to: store)

        XCTAssertEqual(ScanHistoryStore.load(from: store).count, 2, "序列号不同应是两条记录")
    }

    func testHistoryCapsAtLimit() {
        let store = makeIsolatedDefaults()
        ScanHistoryStore.clear(store)
        for i in 0..<(ScanHistoryStore.limit + 5) {
            var info = makeInfo(panel: makePanel())
            info.serialNumber = "SN\(i)"
            info.serialFromIOKit = "SN\(i)"
            ScanHistoryStore.append(ScanSnapshot.make(info: info, battery: makeBattery(), source: "run\(i)"), to: store)
        }
        XCTAssertEqual(ScanHistoryStore.load(from: store).count, ScanHistoryStore.limit)
    }
}
