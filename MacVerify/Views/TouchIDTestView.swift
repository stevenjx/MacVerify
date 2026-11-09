// Views/TouchIDTestView.swift
//
// Touch ID 测试：先判断本机有没有指纹硬件、有没有录入指纹，再真正调起一次认证。
// 结果只有「认证成功」才算通过；取消和失败都如实显示，不当成通过。
import SwiftUI
import LocalAuthentication

struct TouchIDTestView: View {
    @State private var availability: Availability = .checking
    @State private var statusText = ""
    @State private var lastResult: Result = .none
    @State private var isAuthenticating = false

    private enum Availability {
        case checking
        case noHardware
        case notEnrolled
        case ready
    }

    private enum Result {
        case none
        case success
        case failed
        case canceled
    }

    var body: some View {
        PageScroll {
            PageHeader(
                title: "Touch ID",
                subtitle: T("验证指纹传感器能否识别已录入的指纹", "Check that the sensor recognizes an enrolled finger")
            )

            Card(title: T("传感器状态", "Sensor"), icon: "touchid",
                 trailing: AnyView(StatusBadge(text: availabilityText, level: availabilityLevel))) {
                VStack(alignment: .leading, spacing: Space.md) {
                    FactGrid(facts: [
                        Fact(T("硬件", "Hardware"), hardwareText),
                        Fact(T("已录入指纹", "Enrolled"), enrollmentText)
                    ], columns: 2, labelWidth: 84)

                    switch availability {
                    case .noHardware:
                        NoticeBar(text: T("本机没有 Touch ID 传感器（外接键盘上的 Touch ID 也会被识别为可用）。",
                                          "This Mac has no Touch ID sensor. A Magic Keyboard with Touch ID counts as available."),
                                  level: .neutral)
                    case .notEnrolled:
                        NoticeBar(text: T("传感器存在，但系统里没有录入指纹。请先在「系统设置 › Touch ID 与密码」中添加指纹。",
                                          "The sensor is present but no fingerprint is enrolled. Add one in System Settings › Touch ID & Password."),
                                  level: .warning)
                    case .ready:
                        HStack(spacing: Space.sm) {
                            PrimaryButton(title: isAuthenticating
                                          ? T("等待指纹…", "Waiting for finger…")
                                          : T("开始指纹验证", "Verify Fingerprint"),
                                          icon: "touchid") {
                                authenticate()
                            }
                            if isAuthenticating {
                                Text(statusText).font(Typo.caption).foregroundColor(.secondary)
                            }
                        }
                    case .checking:
                        EmptyView()
                    }

                    if lastResult == .success {
                        NoticeBar(text: T("指纹识别成功，传感器工作正常。", "Fingerprint recognized — the sensor works."),
                                  level: .ok)
                    } else if lastResult == .failed {
                        NoticeBar(text: T("指纹未被识别。可再试一次；连续失败请检查传感器表面或重新录入指纹。",
                                          "Fingerprint not recognized. Try again; if it keeps failing, check the sensor surface or re-enroll."),
                                  level: .warning)
                    } else if lastResult == .canceled {
                        NoticeBar(text: T("已取消本次验证，可重新开始。", "Verification canceled; you can start again."),
                                  level: .neutral)
                    }

                    if let message = errorMessage {
                        NoticeBar(text: message, level: .warning)
                    }
                }
            }

            NoticeBar(text: T("验证只用于测试传感器，不读取、不保存任何指纹数据；指纹匹配全部在安全隔区内完成。",
                              "This only exercises the sensor. No fingerprint data is read or stored; matching happens inside the Secure Enclave."),
                      level: .neutral)
        }
        .onAppear { checkAvailability() }
    }

    // MARK: - 判定

    private var context = LAContext()

    private func checkAvailability() {
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        if context.biometryType == .none {
            availability = .noHardware
        } else if canEvaluate {
            availability = .ready
        } else {
            availability = .notEnrolled
        }
    }

    private var availabilityText: String {
        switch availability {
        case .checking: return T("检测中", "Checking")
        case .noHardware: return T("不支持", "Unavailable")
        case .notEnrolled: return T("未录入", "Not enrolled")
        case .ready: return T("可用", "Available")
        }
    }

    private var availabilityLevel: BadgeLevel {
        switch availability {
        case .ready: return .ok
        case .notEnrolled: return .warning
        case .noHardware, .checking: return .neutral
        }
    }

    private var hardwareText: String {
        switch availability {
        case .noHardware: return T("无 Touch ID 传感器", "No Touch ID sensor")
        case .checking: return "—"
        default: return "Touch ID"
        }
    }

    private var enrollmentText: String {
        switch availability {
        case .ready: return T("已录入", "Enrolled")
        case .notEnrolled: return T("未录入", "None")
        case .noHardware: return T("不可用", "Unavailable")
        case .checking: return "—"
        }
    }

    private var errorMessage: String? {
        guard availability == .noHardware else { return nil }
        return T("没有硬件时无法做指纹验证，这一项只能标为不可用。",
                 "Without the hardware there is nothing to verify, so this item stays unavailable.")
    }

    // MARK: - 认证

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        lastResult = .none
        statusText = T("请把手指放在 Touch ID 上", "Place your finger on Touch ID")

        let authContext = LAContext()
        authContext.localizedFallbackTitle = ""
        authContext.localizedCancelTitle = T("取消", "Cancel")

        authContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                   localizedReason: T("验证 Touch ID 传感器是否正常", "check that the Touch ID sensor works")) { success, error in
            Task { @MainActor in
                isAuthenticating = false
                if success {
                    lastResult = .success
                    statusText = ""
                    TestProgress.shared.markCompleted("touchID")
                } else if let code = (error as? LAError)?.code, code == .userCancel || code == .systemCancel {
                    lastResult = .canceled
                    statusText = ""
                } else {
                    lastResult = .failed
                    statusText = ""
                }
            }
        }
    }
}
