// Views/Overview/OverviewIdentityCard.swift
//
// 身份卡：机型、芯片、内存、容量、序列号。只展示事实，不做判断。
// 右侧补三列事实（机壳型号、系统、扫描时间），把卡片横向铺满，
// 而不是让照片左边、文字中间、右边一大片空着。
import SwiftUI

struct OverviewIdentityCard: View {
    let info: MacSystemInfo

    var body: some View {
        HStack(alignment: .center, spacing: Space.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    .fill(Surface.well)
                if let imageName = MacModelCatalog.imageName(for: info.modelIdentifier) {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else {
                    Image(systemName: "laptopcomputer")
                        .font(Typo.icon(30, weight: .light))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 148, height: 92)

            VStack(alignment: .leading, spacing: 3) {
                Text(info.modelDisplayName)
                    .font(Typo.title)
                    .lineLimit(1)

                HStack(spacing: Space.sm) {
                    Text(info.modelIdentifier)
                        .font(Typo.mono)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    if !info.serialValid {
                        StatusBadge(text: T("序列号格式异常", "Unexpected serial"), level: .warning)
                    }
                }

                HStack(spacing: Space.xs + 2) {
                    tag(info.chipName, icon: "cpu")
                    if info.memoryGB > 0 { tag("\(info.memoryGB) GB", icon: "memorychip") }
                    if info.storage.marketingCapacity != "—" {
                        tag(info.storage.marketingCapacity, icon: "internaldrive")
                    }
                }
                .padding(.top, 2)

                HStack(spacing: Space.xs + 2) {
                    Text(T("序列号", "Serial"))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                    Text(info.serialNumber)
                        .font(Typo.mono)
                        .textSelection(.enabled)
                }
                .padding(.top, 1)
            }

            Spacer(minLength: Space.md)

            FactGrid(facts: sideFacts, columns: 1, labelWidth: 56)
                .frame(width: 250)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Surface.fill))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Surface.border, lineWidth: 1)
        )
    }

    private var sideFacts: [Fact] {
        var facts: [Fact] = []
        facts.append(Fact(T("机壳型号", "Model no."),
                          info.modelNumber.isEmpty ? "—" : info.modelNumber,
                          mono: true))
        facts.append(Fact(T("系统", "macOS"), "\(info.osVersion) (\(info.osBuild))", mono: true))
        facts.append(Fact(T("扫描时间", "Scanned"),
                          Format.dateTime(info.scannedAt)))
        return facts
    }

    private func tag(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(Typo.icon(9, weight: .semibold)).foregroundColor(.secondary)
            Text(text).font(Typo.caption).lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(4)
    }
}
