// Views/ComparisonView.swift
//
// F-04：把两次检测结果并排比较。同机不同时间（本机历史快照）或两台机器
// （导入对方导出的报告 JSON）用同一套界面。
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ComparisonView: View {
    @EnvironmentObject private var system: SystemInfoStore
    @EnvironmentObject private var battery: BatteryStore

    @State private var snapshots: [ScanSnapshot] = ScanHistoryStore.load()
    @State private var leftID: UUID?
    @State private var rightID: UUID?
    @State private var importMessage: String?

    var body: some View {
        PageScroll {
            header

            if snapshots.count < 2 {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: T("两次对比", "COMPARISON"), icon: "arrow.left.arrow.right")
                        NoticeBar(
                            text: T("已保存的快照不足两份。每次启动 App 会自动保存一份，也可以点「保存当前状态」。若要对比另一台机器的数据，用「导入报告」载入对方导出的 JSON。",
                                   "Fewer than two snapshots are stored. One is saved automatically on each launch; you can also press Save current state. To compare against another Mac, import the JSON report it exported."),
                            level: .neutral
                        )
                    }
                }
            } else {
                pickers
                if let left = snapshot(leftID), let right = snapshot(rightID) {
                    fingerprintCard(left: left, right: right)
                    diffTable(left: left, right: right)
                }
            }
        }
        .onAppear(perform: reload)
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(T("两次对比", "Comparison")).font(Typo.metric)
                    Text(T("同一台机器的前后变化，或两台机器的差异", "Changes over time, or between two machines"))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                SecondaryButton(title: T("保存当前状态", "Save current"), icon: "square.and.arrow.down") {
                    saveCurrent()
                }
                SecondaryButton(title: T("导入报告", "Import report"), icon: "square.and.arrow.down.on.square") {
                    importReport()
                }
            }
            if let message = importMessage {
                NoticeBar(text: message, level: .neutral)
            }
        }
    }

    // MARK: - 选择对象

    private var pickers: some View {
        Card {
            HStack(spacing: 16) {
                picker(title: T("基准（较早）", "Baseline"), selection: $leftID)
                Image(systemName: "arrow.right").foregroundColor(.secondary)
                picker(title: T("对照（较新）", "Compare to"), selection: $rightID)
                Spacer()
                Button(T("清空历史", "Clear history")) {
                    ScanHistoryStore.clear()
                    reload()
                }
                .buttonStyle(.plain)
                .font(Typo.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    private func picker(title: String, selection: Binding<UUID?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Typo.captionStrong).foregroundColor(.secondary)
            Picker("", selection: selection) {
                ForEach(snapshots) { snapshot in
                    Text("\(snapshot.displayTitle) · \(snapshot.source)").tag(Optional(snapshot.id))
                }
            }
            .labelsHidden()
            .frame(minWidth: 280)
        }
    }

    // MARK: - 指纹

    private func fingerprintCard(left: ScanSnapshot, right: ScanSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: T("报告指纹", "REPORT FINGERPRINT"), icon: "number").padding(.bottom, 2)
                fingerprintRow(title: T("基准", "Baseline"), snapshot: left)
                fingerprintRow(title: T("对照", "Compare to"), snapshot: right)
                Text(T("指纹由机型、序列号、芯片、内存、磁盘容量、面板与电池序列号算出。两份指纹相同说明是同一台机器的同一块硬件；报告字段被改动过则校验不通过。",
                       "The fingerprint is derived from model, serial, chip, memory, disk capacity, panel and battery serial. Equal fingerprints mean the same hardware. If any of those fields were edited, verification fails."))
                    .font(Typo.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fingerprintRow(title: String, snapshot: ScanSnapshot) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Typo.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 76, alignment: .leading)
            Text(DeviceFingerprint.display(snapshot.fingerprint ?? snapshot.recomputedFingerprint))
                .font(Typo.mono)
                .textSelection(.enabled)
            if let matches = snapshot.fingerprintMatches {
                StatusBadge(text: matches ? T("校验通过", "Verified") : T("字段被改过", "Modified"),
                            level: matches ? .ok : .critical)
            } else {
                StatusBadge(text: T("无指纹", "No fingerprint"), level: .neutral)
            }
            Spacer()
        }
    }

    // MARK: - 差异表

    private func diffTable(left: ScanSnapshot, right: ScanSnapshot) -> some View {
        let rows = SnapshotDiff.compare(left, right)
        let changed = SnapshotDiff.changedCount(rows)

        return Card {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SectionHeader(title: T("差异", "DIFFERENCES"), icon: "arrow.left.arrow.right")
                    Spacer()
                    StatusBadge(
                        text: changed == 0
                            ? T("两份完全一致", "Identical")
                            : T("\(changed) 项不同", "\(changed) differences"),
                        level: changed == 0 ? .ok : .warning
                    )
                }
                .padding(.bottom, 8)

                Divider().opacity(Surface.dividerOpacity)

                ForEach(rows) { row in
                    if row.changed {
                        // 上下排新旧值：窄窗口也不会把两列挤成一团
                        HStack(alignment: .top, spacing: Space.sm) {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(StatusPalette.warning)
                                .frame(width: 3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label).font(Typo.bodyStrong)
                                HStack(spacing: Space.xs) {
                                    Text(T("原", "was")).font(Typo.caption).foregroundColor(.secondary)
                                    Text(row.before).font(Typo.mono).foregroundColor(.secondary)
                                }
                                HStack(spacing: Space.xs) {
                                    Text(T("现", "now")).font(Typo.caption).foregroundColor(.secondary)
                                    Text(row.after).font(Typo.mono).foregroundColor(.primary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                    }
                }

                if changed == 0 {
                    Text(T("两份快照的所有可比字段一致。", "Every comparable field is identical."))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - 操作

    private func reload() {
        snapshots = ScanHistoryStore.load()
        if leftID == nil { leftID = snapshots.first?.id }
        if rightID == nil { rightID = snapshots.dropFirst().first?.id ?? snapshots.first?.id }
    }

    private func snapshot(_ id: UUID?) -> ScanSnapshot? {
        guard let id = id else { return nil }
        return snapshots.first { $0.id == id }
    }

    private func saveCurrent() {
        let info = system.info
        guard info.serialValid || info.modelIdentifier != "—" else { return }
        ScanHistoryStore.append(.make(info: info, battery: battery.battery, source: T("本机扫描", "Local scan")))
        reload()
        importMessage = T("已保存当前状态。", "Current state saved.")
    }

    private func importReport() {
        let panel = NSOpenPanel()
        panel.title = T("导入质检报告", "Import inspection report")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else {
            importMessage = T("无法读取该文件。", "Could not read that file.")
            return
        }
        guard let snapshot = ScanSnapshot.make(reportJSON: data, source: url.lastPathComponent) else {
            importMessage = T("这不是 MacVerify 导出的报告 JSON。", "That is not a MacVerify report JSON.")
            return
        }
        ScanHistoryStore.append(snapshot)
        reload()
        importMessage = T("已导入 \(url.lastPathComponent)。", "Imported \(url.lastPathComponent).")
    }
}
