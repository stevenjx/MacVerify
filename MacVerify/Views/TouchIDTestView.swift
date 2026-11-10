// Views/TouchIDTestView.swift
//
// Touch ID：不只是「传感器能不能认指纹」，而是把整条录入链路走一遍。
//
// 录入本身只能由系统完成（macOS 要求管理员在「系统设置」里按指纹），
// App 能如实做的是四件事，顺序也正是用户实际遇到的顺序：
//   1. 有没有传感器（本机 Touch ID / 妙控键盘 Touch ID / Face ID）
//   2. 系统准备（有没有登录密码、生物识别是否被锁定）
//   3. 指纹是否已录入（没有就引导去系统设置，回来后自动复查）
//   4. 真正调一次认证，确认认得出
// 只有第 4 步成功才算这一项通过——前面三步成立但验证失败，仍然是失败。
import SwiftUI
import LocalAuthentication
import AppKit

@MainActor
final class TouchIDModel: ObservableObject {

    enum Sensor: Equatable {
        case touchID, faceID, opticID, none
    }

    /// 系统层面的可用性，来源是 LAContext 的错误码，不做猜测
    enum Phase: Equatable {
        case unknown
        case ready            // 有硬件、有密码、已录入
        case notEnrolled      // 有硬件，但没有指纹
        case noPasscode       // 没设登录密码，生物识别无法启用
        case lockedOut        // 连续失败被锁定，需要密码解锁
        case unavailable      // 没有硬件或系统禁用
    }

    enum VerifyResult: Equatable {
        case none, success, failed, canceled, lockedOut
    }

    struct Step: Identifiable {
        let id: String
        let index: Int
        let title: String
        let detail: String
        let status: Status

        enum Status {
            case pending, active, passed, failed, unavailable
        }
    }

    @Published private(set) var sensor: Sensor = .none
    @Published private(set) var phase: Phase = .unknown
    @Published private(set) var isVerifying = false
    @Published private(set) var verifyResult: VerifyResult = .none
    @Published private(set) var attempts = 0
    @Published private(set) var message: String?

    // MARK: - 检测

    func refresh() {
        let context = LAContext()
        var error: NSError?
        let canBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        sensor = Self.sensor(from: context.biometryType)

        let biometricCode = (error as? LAError)?.code

        var deviceError: NSError?
        let canDevice = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &deviceError)
        let deviceCode = (deviceError as? LAError)?.code

        if sensor == .none {
            phase = .unavailable
        } else if deviceCode == .passcodeNotSet {
            phase = .noPasscode
        } else if biometricCode == .biometryLockout {
            phase = .lockedOut
        } else if canBiometrics {
            phase = .ready
        } else if biometricCode == .biometryNotEnrolled {
            phase = .notEnrolled
        } else if biometricCode == .biometryNotAvailable {
            phase = .unavailable
        } else {
            // 兜底：拿不到明确错误码时，只有「系统级认证可用」才当作未录入
            phase = canDevice ? .notEnrolled : .unavailable
        }

    }

    private static func sensor(from type: LABiometryType) -> Sensor {
        switch type {
        case .touchID: return .touchID
        case .faceID: return .faceID
        case .none: return .none
        default:
            if #available(macOS 14.0, *), type == .opticID { return .opticID }
            return .none
        }
    }

    // MARK: - 步骤

    var steps: [Step] {
        [
            Step(id: "hardware", index: 1,
                 title: T("传感器", "Sensor"),
                 detail: sensorDetail,
                 status: sensor == .none ? .failed : .passed),

            Step(id: "system", index: 2,
                 title: T("系统准备", "System readiness"),
                 detail: systemDetail,
                 status: systemStatus),

            Step(id: "enrollment", index: 3,
                 title: T("指纹录入", "Fingerprint enrolled"),
                 detail: enrollmentDetail,
                 status: enrollmentStatus),

            Step(id: "verify", index: 4,
                 title: T("指纹验证", "Verification"),
                 detail: verifyDetail,
                 status: verifyStatus)
        ]
    }

    var isComplete: Bool {
        sensor != .none && phase == .ready && verifyResult == .success
    }

    var hardwareText: String {
        switch sensor {
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        case .none: return T("无传感器", "None")
        }
    }

    var enrollmentText: String {
        switch phase {
        case .ready: return T("已录入", "Enrolled")
        case .notEnrolled: return T("未录入", "None")
        case .noPasscode, .lockedOut: return T("暂不可用", "Unavailable")
        case .unavailable: return T("不可用", "Unavailable")
        case .unknown: return "—"
        }
    }

    private var sensorDetail: String {
        switch sensor {
        case .touchID:
            return T("检测到 Touch ID（内置键盘或妙控键盘）。", "Touch ID detected (built-in or Magic Keyboard).")
        case .faceID:
            return T("检测到 Face ID。", "Face ID detected.")
        case .opticID:
            return T("检测到 Optic ID。", "Optic ID detected.")
        case .none:
            return T("这台 Mac 没有可用的生物识别传感器，后面三步无从进行。",
                     "No biometric sensor is available on this Mac, so the remaining steps cannot run.")
        }
    }

    private var systemStatus: Step.Status {
        switch phase {
        case .unknown: return .pending
        case .noPasscode: return .failed
        case .lockedOut: return .active
        case .unavailable: return sensor == .none ? .pending : .failed
        default: return .passed
        }
    }

    private var systemDetail: String {
        switch phase {
        case .unknown:
            return T("正在读取系统状态…", "Reading system state…")
        case .noPasscode:
            return T("没有登录密码，生物识别无法启用。请先在「系统设置 › Touch ID 与密码」设置密码。",
                     "No login password is set, so biometrics cannot be enabled. Set one in System Settings › Touch ID & Password.")
        case .lockedOut:
            return T("生物识别因连续失败被锁定。用登录密码解锁一次即可恢复。",
                     "Biometrics are locked after repeated failures. Unlock once with the login password.")
        case .unavailable:
            return T("系统未提供生物识别能力。", "The system does not offer biometric authentication.")
        default:
            return T("登录密码已设置，生物识别可被系统调起。",
                     "A login password is set and biometrics can be invoked.")
        }
    }

    private var enrollmentStatus: Step.Status {
        switch phase {
        case .ready: return .passed
        case .notEnrolled: return .active
        case .lockedOut, .noPasscode, .unavailable, .unknown: return .pending
        }
    }

    private var enrollmentDetail: String {
        switch phase {
        case .ready:
            return attempts > 0
                ? T("已录入并可验证（本次已验证 \(attempts) 次）", "Enrolled and verified (\(attempts) attempt(s) this session)")
                : T("系统里已有可用的指纹。", "A usable fingerprint is already enrolled.")
        case .notEnrolled:
            return T("系统里还没有指纹。录入只能由系统完成：点「打开 Touch ID 设置」按提示添加，回到本页会自动复查。",
                     "No fingerprint is enrolled yet. Only the system can enrol: open Touch ID settings, add one, and this page re-checks when you come back.")
        case .noPasscode:
            return T("先设置登录密码，才能录入指纹。", "Set a login password before enrolling a fingerprint.")
        case .lockedOut:
            return T("解锁后再确认录入状态。", "Unlock first, then re-check enrollment.")
        case .unavailable:
            return T("没有传感器，无法录入。", "Without a sensor there is nothing to enroll.")
        case .unknown:
            return "—"
        }
    }

    private var verifyStatus: Step.Status {
        if phase != .ready { return .pending }
        switch verifyResult {
        case .success: return .passed
        case .failed, .lockedOut: return .failed
        case .canceled, .none: return .active
        }
    }

    private var verifyDetail: String {
        if phase != .ready {
            return T("录入完成后才能验证。", "Verification becomes available once a fingerprint is enrolled.")
        }
        switch verifyResult {
        case .success:
            return T("指纹识别成功，传感器与录入都正常。", "Fingerprint recognized — sensor and enrollment both work.")
        case .failed:
            return T("指纹未被识别。可再试一次；连续失败请检查传感器表面。",
                     "Fingerprint not recognized. Try again; if it keeps failing, check the sensor surface.")
        case .canceled:
            return T("上次验证被取消，可重新开始。", "The last attempt was canceled; start again anytime.")
        case .lockedOut:
            return T("连续失败导致锁定，需用登录密码解锁。", "Locked after repeated failures; unlock with the login password.")
        case .none:
            return T("点「验证指纹」，把手放在传感器上确认识别正常。",
                     "Press Verify Fingerprint and place your finger on the sensor.")
        }
    }

    // MARK: - 动作

    func verify() {
        guard !isVerifying, phase == .ready else { return }
        isVerifying = true
        verifyResult = .none
        message = nil

        let context = LAContext()
        context.localizedFallbackTitle = ""
        context.localizedCancelTitle = T("取消", "Cancel")

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: T("验证 Touch ID 能否识别已录入的指纹",
                                                  "check that Touch ID recognizes the enrolled fingerprint")) { success, error in
            Task { @MainActor in
                self.isVerifying = false
                if success {
                    self.attempts += 1
                    self.verifyResult = .success
                    TestProgress.shared.markCompleted("touchID")
                    self.refresh()
                    return
                }
                switch (error as? LAError)?.code {
                case .userCancel, .systemCancel, .appCancel:
                    self.verifyResult = .canceled
                case .biometryLockout:
                    self.verifyResult = .lockedOut
                    self.message = T("已锁定：请用登录密码解锁后再试。", "Locked out: unlock with your login password and try again.")
                default:
                    self.verifyResult = .failed
                    if let error = error { self.message = error.localizedDescription }
                }
                self.refresh()
            }
        }
    }

    /// 锁定状态下用「密码或指纹」把生物识别解回来
    func unlock() {
        guard !isVerifying else { return }
        isVerifying = true
        let context = LAContext()
        context.localizedFallbackTitle = T("使用密码", "Use Password")
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: T("用登录密码解锁 Touch ID", "unlock Touch ID with the login password")) { success, error in
            Task { @MainActor in
                self.isVerifying = false
                if success {
                    self.message = T("已解锁，可以继续验证。", "Unlocked — you can verify now.")
                } else if let error = error {
                    self.message = error.localizedDescription
                }
                self.refresh()
            }
        }
    }

    /// 录入只能在系统设置里做；这里只负责把用户送过去
    func openEnrollmentSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Touch-ID-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.security?TouchID"
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
        message = T("无法自动打开系统设置，请手动前往「系统设置 › Touch ID 与密码」。",
                    "Could not open System Settings automatically; go to System Settings › Touch ID & Password.")
    }
}

struct TouchIDTestView: View {
    @StateObject private var model = TouchIDModel()

    var body: some View {
        PageScroll {
            PageHeader(
                title: "Touch ID",
                subtitle: T("完整走一遍：传感器 → 系统准备 → 指纹录入 → 验证",
                            "Full path: sensor, system readiness, enrollment, verification"),
                trailing: AnyView(StatusBadge(text: overallText, level: overallLevel))
            )

            Card(title: T("录入流程", "Enrollment path"), icon: "touchid") {
                VStack(alignment: .leading, spacing: 0) {
                    FactGrid(facts: [
                        Fact(T("传感器", "Sensor"), model.hardwareText),
                        Fact(T("指纹", "Fingerprints"), model.enrollmentText)
                    ], columns: 2, labelWidth: 84)

                    Rectangle().fill(Surface.hairline).frame(height: 1)
                        .padding(.vertical, Space.md)

                    VStack(alignment: .leading, spacing: Space.md) {
                        ForEach(model.steps) { step in
                            stepRow(step)
                        }
                    }

                    if let message = model.message {
                        NoticeBar(text: message, level: .warning)
                            .padding(.top, Space.md)
                    }

                    actionRow
                        .padding(.top, Space.md)
                }
            }

            if model.verifyResult == .success {
                NoticeBar(text: T("四步全部走通：传感器存在、系统就绪、指纹已录入、认证成功。",
                                  "All four steps passed: the sensor exists, the system is ready, a fingerprint is enrolled, and authentication succeeded."),
                          level: .ok)
            }

            NoticeBar(text: T("录入只能由系统完成，App 不读取、不保存任何指纹数据；指纹比对全部在安全隔区内进行。",
                              "Only the system can enrol fingerprints. This app reads and stores no fingerprint data; matching happens inside the Secure Enclave."),
                      level: .neutral)
        }
        .onAppear { model.refresh() }
        // 从系统设置录完指纹切回来，自动复查：用户不必手动点刷新
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    // MARK: - 行与动作

    private func stepRow(_ step: TouchIDModel.Step) -> some View {
        HStack(alignment: .top, spacing: Space.md) {
            ZStack {
                Circle()
                    .fill(symbolColor(step.status).opacity(step.status == .pending ? 0.08 : 0.14))
                    .frame(width: 20, height: 20)
                if step.status == .passed {
                    Image(systemName: "checkmark")
                        .font(Typo.icon(9, weight: .bold))
                        .foregroundColor(symbolColor(step.status))
                } else if step.status == .failed {
                    Image(systemName: "xmark")
                        .font(Typo.icon(9, weight: .bold))
                        .foregroundColor(symbolColor(step.status))
                } else {
                    Text("\(step.index)")
                        .font(Typo.icon(9, weight: .semibold))
                        .foregroundColor(symbolColor(step.status))
                }
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(Typo.bodyStrong)
                    .foregroundColor(step.status == .pending ? .secondary : .primary)
                Text(step.detail)
                    .font(Typo.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Space.sm)

            trailingMark(step.status)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func trailingMark(_ status: TouchIDModel.Step.Status) -> some View {
        switch status {
        case .passed:
            // 左侧圆片已经是勾，这里再画一次只会重复
            EmptyView()
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Typo.icon(11, weight: .semibold))
                .foregroundColor(StatusPalette.critical)
        case .active:
            Text(T("待完成", "Pending"))
                .font(Typo.caption)
                .foregroundColor(StatusPalette.warning)
        case .pending, .unavailable:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: Space.sm) {
            switch model.phase {
            case .ready:
                PrimaryButton(title: model.isVerifying
                              ? T("等待指纹…", "Waiting for finger…")
                              : T("验证指纹", "Verify Fingerprint"),
                              icon: "touchid",
                              enabled: !model.isVerifying) {
                    model.verify()
                }
                Text(T("把手放在 Touch ID 上，直到提示成功。", "Keep your finger on Touch ID until it reports success."))
                    .font(Typo.caption)
                    .foregroundColor(.secondary)

            case .notEnrolled:
                PrimaryButton(title: T("打开 Touch ID 设置", "Open Touch ID settings"),
                              icon: "gearshape", enabled: true) {
                    model.openEnrollmentSettings()
                }
                SecondaryButton(title: T("我已录入，复查", "I enrolled — re-check"), icon: "arrow.clockwise") {
                    model.refresh()
                }
                Text(T("在系统设置里添加指纹后回到本页，会自动复查。",
                       "Add a fingerprint, come back, and this page re-checks on its own."))
                    .font(Typo.caption)
                    .foregroundColor(.secondary)

            case .lockedOut:
                PrimaryButton(title: T("用密码解锁", "Unlock with password"),
                              icon: "lock.open", enabled: !model.isVerifying) {
                    model.unlock()
                }
                Text(T("生物识别被锁定后，只能用登录密码解开。",
                       "After a lockout, only the login password can unlock biometrics."))
                    .font(Typo.caption)
                    .foregroundColor(.secondary)

            case .noPasscode:
                SecondaryButton(title: T("打开 Touch ID 设置", "Open Touch ID settings"), icon: "gearshape") {
                    model.openEnrollmentSettings()
                }
                Text(T("先设置登录密码，生物识别才可用。", "Set a login password first; biometrics need it."))
                    .font(Typo.caption)
                    .foregroundColor(.secondary)

            case .unavailable, .unknown:
                SecondaryButton(title: T("重新检测", "Check again"), icon: "arrow.clockwise") {
                    model.refresh()
                }
                Text(model.sensor == .none
                     ? T("没有传感器时这一项只能标为不可用。", "Without a sensor this item can only be marked unavailable.")
                     : T("系统暂未提供生物识别能力。", "The system is not offering biometric authentication."))
                    .font(Typo.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func symbolColor(_ status: TouchIDModel.Step.Status) -> Color {
        switch status {
        case .passed: return StatusPalette.ok
        case .failed: return StatusPalette.critical
        case .active: return StatusPalette.warning
        case .pending, .unavailable: return StatusPalette.neutral
        }
    }

    private var overallText: String {
        if model.sensor == .none { return T("不可用", "Unavailable") }
        if model.isComplete { return T("通过", "Passed") }
        return T("待完成", "In progress")
    }

    private var overallLevel: BadgeLevel {
        if model.sensor == .none { return .neutral }
        return model.isComplete ? .ok : .warning
    }
}
