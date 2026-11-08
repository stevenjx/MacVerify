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
            PageHeader(
                title: T("两次对比", "Comparison"),
                subtitle: T("同一台机器的前后变化，或两台机器的差异", "Changes over time, or between two machines"),
                trailing: AnyView(
                    HStack(spacing: Space.sm) {
                        SecondaryButton(title: T("保存当前状态", "Save current"), icon: "square.and.arrow.down") {
                            saveCurrent()
                        }
                        SecondaryButton(title: T("导入报告", "Import report"), icon: "square.and.arrow.down.on.square") {
                            importReport()
                        }
                    }
                )
            )

            if let message = importMessage {
                NoticeBar(text: message, level: .neutral)
            }

            if snapshots.count < 2 {
                Card(title: T("如何对比", "How to compare"), icon: "arrow.left.arrow.right") {
                    Text(T("已保存的快照不足两份。每次启动 App 会自动保存一份，也可以点「保存当前状态」。若要对比另一台机器的数据，用「导入报告」载入对方导出的 JSON。",
                           "Fewer than two snapshots are stored. One is saved automatically on each launch; you can also press Save current state. To compare against another Mac, import the JSON report it exported."))
                        .font(Typo.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                snapshotList
            } else {
                pickers
                if let left = snapshot(leftID), let right = snapshot(rightID) {
                    HStack(alignment: .top, spacing: Metrics.pageGap) {
                        fingerprintCard(title: T("基准（较早）", "Baseline"), snapshot: left)
                        fingerprintCard(title: T("对照（较新）", "Compare to"), snapshot: right)
                    }
                    diffTable(left: left, right: right)
                }
            }
        }
        .onAppear(perform: reload)
    }

    /// 快照不足两份时，把已存的列出来：用户能看到「存了什么」，也知道再存一份就能对比。
    private var snapshotList: some View {
        Card(title: T("已保存的快照", "Saved snapshots"), icon: "tray.full",
             trailing: AnyView(
                Text(T("\(snapshots.count) / \(ScanHistoryStore.limit)", "\(snapshots.count) of \(ScanHistoryStore.limit)"))
                    .font(Typo.caption)
                    .foregroundColor(.secondary)
             )) {
            VStack(spacing: 0) {
                ForEach(Array(snapshots.prefix(6).enumerated()), id: \.element.id) { index, snapshot in
                    HStack(spacing: Space.sm) {
                        Text(snapshot.displayTitle).font(Typo.caption).lineLimit(1)
                        Text(snapshot.source).font(Typo.mono).foregroundColor(.secondary).lineLimit(1)
                        Spacer(minLength: Space.sm)
                        Text(DeviceFingerprint.display(snapshot.fingerprint ?? snapshot.recomputedFingerprint))
                            .font(Typo.mono)
                            .foregroundColor(.secondary)
                        if let matches = snapshot.fingerprintMatches {
                            StatusBadge(text: matches ? T("校验通过", "Verified") : T("字段被改过", "Modified"),
                                        level: matches ? .ok : .critical)
                        }
                    }
                    .frame(height: Metrics.row)
                    if index < min(snapshots.count, 6) - 1 {
                        Rectangle().fill(Surface.hairline).frame(height: 1)
                    }
                }
            }
        }
    }

    // MARK: - 选择对象

    private var pickers: some View {
        Card(title: T("对比对象", "Compare"), icon: "slider.horizontal.3",
             trailing: AnyView(
                Button(T("清空历史", "Clear history")) {
                    ScanHistoryStore.clear()
                    reload()
                }
                .buttonStyle(.plain)
                .font(Typo.caption)
                .foregroundColor(.secondary)
             )) {
            HStack(spacing: Space.md) {
                picker(title: T("基准", "Baseline"), selection: $leftID)
                Image(systemName: "arrow.right")
                    .font(Typo.icon(10, weight: .semibold))
                    .foregroundColor(.secondary)
                picker(title: T("对照", "Compare to"), selection: $rightID)
            }
        }
    }

    private func picker(title: String, selection: Binding<UUID?>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Typo.caption).foregroundColor(.secondary)
            Picker("", selection: selection) {
                ForEach(snapshots) { snapshot in
                    Text("\(snapshot.displayTitle) · \(snapshot.source)").tag(Optional(snapshot.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 指纹

    private func fingerprintCard(title: String, snapshot: ScanSnapshot) -> some View {
        Card(title: title, icon: "number") {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    Text(DeviceFingerprint.display(snapshot.fingerprint ?? snapshot.recomputedFingerprint))
                        .font(Typo.mono)
                        .textSelection(.enabled)
                    if let matches = snapshot.fingerprintMatches {
                        StatusBadge(text: matches ? T("校验通过", "Verified") : T("字段被改过", "Modified"),
                                    level: matches ? .ok : .critical)
                    } else {
                        StatusBadge(text: T("无指纹", "No fingerprint"), level: .neutral)
                    }
                    Spacer(minLength: 0)
                }
                Text(T("指纹由机型、序列号、芯片、内存、磁盘容量、面板与电池序列号算出；字段被改动则校验不通过。",
                       "Derived from model, serial, chip, memory, disk capacity, panel and battery serial. Edited fields fail verification."))
                    .font(Typo.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - 差异表

    private func diffTable(left: ScanSnapshot, right: ScanSnapshot) -> some View {
        let rows = SnapshotDiff.compare(left, right)
        let changed = SnapshotDiff.changedCount(rows)
        let changedRows = rows.filter(\.changed)

        return Card(title: T("差异", "Differences"), icon: "arrow.left.arrow.right",
                    trailing: AnyView(
                        StatusBadge(
                            text: changed == 0
                                ? T("两份完全一致", "Identical")
                                : T("\(changed) / \(rows.count) 项不同", "\(changed) of \(rows.count) differ"),
                            level: changed == 0 ? .ok : .warning
                        )
                    )) {
            if changed == 0 {
                Text(T("两份快照的所有可比字段一致。", "Every comparable field is identical."))
                    .font(Typo.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: Space.sm) {
                        Text(T("项目", "Field")).frame(width: 170, alignment: .leading)
                        Text(T("基准", "Baseline")).frame(maxWidth: .infinity, alignment: .leading)
                        Text(T("对照", "Compare to")).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(Typo.captionStrong)
                    .foregroundColor(.secondary)
                    .frame(height: 22)

                    Rectangle().fill(Surface.hairline).frame(height: 1)

                    ForEach(changedRows) { row in
                        HStack(spacing: Space.sm) {
                            Text(row.label)
                                .font(Typo.caption)
                                .frame(width: 170, alignment: .leading)
                                .lineLimit(1)
                            Text(row.before)
                                .font(Typo.mono)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                            Text(row.after)
                                .font(Typo.mono)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                        }
                        .frame(height: Metrics.row)
                        .background(StatusPalette.warning.opacity(0.05))

                        Rectangle().fill(Surface.hairline).frame(height: 1)
                    }
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
