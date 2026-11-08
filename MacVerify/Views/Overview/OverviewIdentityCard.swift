// Views/Overview/OverviewIdentityCard.swift
import SwiftUI

/// 身份卡：机型、芯片、内存、容量、序列号。只展示事实，不做判断。
struct OverviewIdentityCard: View {
    let info: MacSystemInfo

    var body: some View {
        HStack(alignment: .center, spacing: Space.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                if let imageName = MacModelCatalog.imageName(for: info.modelIdentifier) {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(Space.sm)
                } else {
                    Image(systemName: "laptopcomputer")
                        .font(Typo.icon(36, weight: .light))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 190, height: 116)

            VStack(alignment: .leading, spacing: Space.xs + 2) {
                Text(info.modelDisplayName)
                    .font(Typo.title)
                Text(info.modelIdentifier)
                    .font(Typo.mono)
                    .foregroundColor(.secondary)

                HStack(spacing: Space.sm) {
                    tag(info.chipName, icon: "cpu")
                    if info.memoryGB > 0 { tag("\(info.memoryGB) GB", icon: "memorychip") }
                    if info.storage.marketingCapacity != "—" {
                        tag(info.storage.marketingCapacity, icon: "internaldrive")
                    }
                }
                .padding(.top, 2)

                HStack(spacing: Space.xs + 2) {
                    Text(T("序列号", "Serial"))
                        .font(Typo.body)
                        .foregroundColor(.secondary)
                    Text(info.serialNumber)
                        .font(Typo.mono)
                        .textSelection(.enabled)
                    if !info.serialValid {
                        StatusBadge(text: T("格式异常", "Unexpected format"), level: .warning)
                    }
                }
                .padding(.top, 2)
            }

            Spacer()
        }
        .padding(Space.lg)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Surface.fill))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .stroke(Surface.border, lineWidth: 1)
        )
    }

    private func tag(_ text: String, icon: String) -> some View {
        HStack(spacing: Space.xs) {
            Image(systemName: icon).font(Typo.icon(10, weight: .semibold)).foregroundColor(.secondary)
            Text(text).font(Typo.caption)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(Radius.tile)
    }
}
