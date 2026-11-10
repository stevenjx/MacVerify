// Views/TouchIDTestView.swift
//
// Touch ID：把「录入一枚新指纹」的完整过程放在这个页面里走一遍。
//
// 有一条不能含糊的技术边界：指纹模板只能由系统写入，macOS 没有给第三方 App
// 提供任何录入接口（LocalAuthentication 里只有「校验」，没有「录入」）。
// 所以真正按手指的那一步发生在系统面板里，本页做的是把它变成可验证的过程：
//   - 按系统面板的顺序，把同样的五步摆在这里；
//   - 进面板前记下 `bioutil -c` 的模板数，录入期间每秒复查；
//   - 数量 +1 才算「这枚真的录进去了」，之后才允许进入验证。
// 没有动画式的假进度：没录进去就是没录进去。
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

    @Published private(set) var sensor: Sensor = .none
    @Published private(set) var phase: Phase = .unknown
    @Published private(set) var isVerifying = false
    @Published private(set) var verifyResult: VerifyResult = .none
    @Published private(set) var attempts = 0
    @Published private(set) var message: String?

    /// 系统里当前有几枚指纹模板（bioutil -c）
    @Published private(set) var templateCount: Int?
    /// 本次录入开始前的数量。用来判断「这一枚是刚录进去的」
    @Published private(set) var baseline: Int?
    @Published private(set) var isWatching = false
    @Published private(set) var didEnroll = false

    private var watchTimer: Timer?

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

        if !isWatching { templateCount = BiometricTemplates.count() }
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

    // MARK: - 展示用文字

    var hardwareText: String {
        switch sensor {
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        case .none: return T("无传感器", "None")
        }
    }

    var templateText: String {
        switch templateCount {
        case .some(let count): return T("\(count) 枚", "\(count)")
        case .none: return T("读不到", "Unavailable")
        }
    }

    var enrollmentBadge: (text: String, level: BadgeLevel) {
        if sensor == .none { return (T("不可用", "Unavailable"), .neutral) }
        if isWatching { return (T("录入中", "Enrolling"), .warning) }
        if didEnroll { return (T("已录入", "Enrolled"), .ok) }
        switch phase {
        case .ready: return (T("已录入", "Enrolled"), .ok)
        case .notEnrolled: return (T("未录入", "Not enrolled"), .warning)
        case .lockedOut: return (T("已锁定", "Locked out"), .critical)
        case .noPasscode: return (T("缺登录密码", "No password"), .critical)
        case .unavailable, .unknown: return (T("不可用", "Unavailable"), .neutral)
        }
    }

    /// 录入面板里的五个步骤，与系统面板的顺序一致
    var enrollmentSteps: [String] {
        [
            T("打开「系统设置 › Touch ID 与密码」，点「添加指纹」。",
              "Open System Settings › Touch ID & Password and click Add Fingerprint."),
            T("输入登录密码——这一步由系统校验，App 无法代劳。",
              "Enter the login password. Only the system can check it."),
            T("把手指放在传感器上，保持不动，直到系统提示抬起。",
              "Rest your finger on the sensor and hold still until it asks you to lift."),
            T("抬起后再次放上，重复到系统提示完成（通常 8 次左右）。",
              "Lift and place again; repeat about eight times until the system says it is done."),
            T("按提示调整手指角度，再补录指尖与边缘，然后命名这枚指纹。",
              "Adjust the angle as prompted to capture the fingertip and edges, then name it.")
        ]
    }

    /// 录入过程中的实时状态。基线未知时只说数量，不编造进度。
    var liveText: String? {
        guard isWatching else { return nil }
        switch (baseline, templateCount) {
        case let (base?, current?):
            return T("等待系统写入… 已录入 \(current) 枚（开始时 \(base) 枚）",
                     "Waiting for the system to write… \(current) enrolled (started at \(base))")
        case let (_, current?):
            return T("等待系统写入… 已录入 \(current) 枚", "Waiting for the system to write… \(current) enrolled")
        default:
            return T("等待系统写入…", "Waiting for the system to write…")
        }
    }

    var verifyDetail: String {
        if phase != .ready {
            return T("录入完成后才能验证。", "Verification becomes available once a fingerprint is enrolled.")
        }
        switch verifyResult {
        case .success:
            return T("指纹识别成功，录入与传感器都正常。", "Fingerprint recognized — enrollment and sensor both work.")
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

    // MARK: - 录入向导

    /// 记下当前模板数，打开系统录入面板，然后每秒复查一次数量
    func beginEnrollment() {
        baseline = BiometricTemplates.count()
        templateCount = baseline
        didEnroll = false
        message = nil
        isWatching = true
        openEnrollmentSettings()
        startWatching()
    }

    func stopWatching() {
        watchTimer?.invalidate()
        watchTimer = nil
        isWatching = false
    }

    private func startWatching() {
        watchTimer?.invalidate()
        let timer = Timer(timeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // 系统面板可能让主 RunLoop 进入 modal 模式，必须挂 common 才会继续跑
        RunLoop.main.add(timer, forMode: .common)
        watchTimer = timer
    }

    private func tick() {
        guard isWatching else { return }
        let current = BiometricTemplates.count()
        templateCount = current
        guard let base = baseline, let current = current, current != base else { return }

        stopWatching()
        if current > base {
            didEnroll = true
            message = T("检测到新指纹：模板数 \(base) → \(current)，系统已写入。",
                        "New fingerprint detected: templates \(base) → \(current), written by the system.")
        } else {
            didEnroll = false
            message = T("检测到指纹数量减少：模板数 \(base) → \(current)。",
                        "Fewer fingerprints than before: templates \(base) → \(current).")
        }
        refresh()
    }

    // MARK: - 验证

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
                    self.message = T("已解锁，可以继续录入或验证。", "Unlocked — you can enroll or verify now.")
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
                subtitle: T("按系统面板的顺序录入一枚新指纹，并核对它真的写进去了",
                            "Enrol a new fingerprint in the system's own order, then check it actually landed"),
                trailing: AnyView(StatusBadge(text: model.enrollmentBadge.text, level: model.enrollmentBadge.level))
            )

            enrollmentCard
            verificationCard

            if let message = model.message {
                NoticeBar(text: message, level: model.didEnroll ? .ok : .warning)
            }

            NoticeBar(text: T("指纹模板只能由系统写入：App 不读取、不保存任何指纹数据，也无法代你录入；这里做的是把同样的步骤摆出来，并用系统返回的模板数量确认结果。",
                              "Only the system can write fingerprint templates. This app reads and stores no fingerprint data and cannot enrol on your behalf; it lays out the same steps and confirms the result with the system's template count."),
                      level: .neutral)
        }
        .onAppear { model.refresh() }
        .onDisappear { model.stopWatching() }
        // 从系统设置录完指纹切回来，立刻复查一次，不必等下一拍
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    // MARK: - 录入

    private var enrollmentCard: some View {
        Card(title: T("录入新指纹", "Enrol a fingerprint"), icon: "touchid") {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .top, spacing: Space.xl) {
                    FactGrid(facts: [
                        Fact(T("传感器", "Sensor"), model.hardwareText),
                        Fact(T("已录入", "Fingerprints"), model.templateText)
                    ], columns: 2, labelWidth: 76)
                        .frame(maxWidth: 360, alignment: .leading)

                    Spacer(minLength: Space.md)

                    if model.isWatching {
                        HStack(spacing: Space.xs) {
                            ProgressView().controlSize(.small).scaleEffect(0.65).frame(width: 12, height: 12)
                            Text(model.liveText ?? "")
                                .font(Typo.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: 420, alignment: .leading)
                    }
                }

                Rectangle().fill(Surface.hairline).frame(height: 1)

                // 与系统面板同序的五步；编号而不是勾，因为这些步骤 App 看不到中间状态
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(model.enrollmentSteps.enumerated()), id: \.offset) { index, text in
                        HStack(alignment: .top, spacing: Space.sm) {
                            Text(String(format: "%02d", index + 1))
                                .font(Typo.mono)
                                .foregroundColor(.secondary)
                                .frame(width: 18, alignment: .trailing)
                            Text(text)
                                .font(Typo.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                actionRow
            }
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: Space.sm) {
            if model.sensor != .none && model.phase != .noPasscode {
                PrimaryButton(title: model.isWatching
                              ? T("正在等待系统写入…", "Waiting for the system…")
                              : T("开始录入", "Start enrolling"),
                              icon: "touchid",
                              enabled: !model.isWatching) {
                    model.beginEnrollment()
                }
            }

            if model.isWatching {
                SecondaryButton(title: T("停止监听", "Stop watching"), icon: "stop.fill") {
                    model.stopWatching()
                }
            }

            if model.phase == .lockedOut {
                SecondaryButton(title: T("用密码解锁", "Unlock with password"),
                                icon: "lock.open", enabled: !model.isVerifying) {
                    model.unlock()
                }
            }

            if model.phase == .noPasscode {
                SecondaryButton(title: T("打开 Touch ID 设置", "Open Touch ID settings"), icon: "gearshape") {
                    model.openEnrollmentSettings()
                }
            }

            if model.didEnroll {
                SecondaryButton(title: T("再录一枚", "Enrol another"), icon: "plus") {
                    model.beginEnrollment()
                }
            }

            Text(hintText)
                .font(Typo.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520, alignment: .leading)

            Spacer(minLength: 0)
        }
    }

    private var hintText: String {
        switch model.phase {
        case .unavailable:
            return T("这台 Mac 没有可用的生物识别传感器，无法录入。",
                     "No biometric sensor is available, so there is nothing to enrol.")
        case .noPasscode:
            return T("先设置登录密码，生物识别才能启用。", "Set a login password first; biometrics need it.")
        case .lockedOut:
            return T("生物识别被锁定后，只能用登录密码解开。", "After a lockout, only the login password can unlock biometrics.")
        default:
            return model.didEnroll
                ? T("这枚已经写进系统，接下来验证它能不能被识别。", "It is written; now check that it can be recognized.")
                : T("点「开始录入」会打开系统面板；面板里完成录入后，这里会自动确认。",
                    "Start enrolling opens the system panel; the count here updates when it is written.")
        }
    }

    // MARK: - 验证

    private var verificationCard: some View {
        Card(title: T("验证指纹", "Verify"), icon: "checkmark.seal",
             trailing: AnyView(verifyBadge)) {
            VStack(alignment: .leading, spacing: Space.sm) {
                Text(model.verifyDetail)
                    .font(Typo.body)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Space.sm) {
                    PrimaryButton(title: model.isVerifying
                                  ? T("等待指纹…", "Waiting for finger…")
                                  : T("验证指纹", "Verify Fingerprint"),
                                  icon: "touchid",
                                  enabled: !model.isVerifying && model.phase == .ready) {
                        model.verify()
                    }
                    if model.attempts > 0 {
                        Text(T("本次已通过 \(model.attempts) 次", "\(model.attempts) successful attempt(s) this session"))
                            .font(Typo.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var verifyBadge: some View {
        switch model.verifyResult {
        case .success:
            return StatusBadge(text: T("通过", "Passed"), level: .ok)
        case .failed, .lockedOut:
            return StatusBadge(text: T("未通过", "Failed"), level: .critical)
        case .canceled:
            return StatusBadge(text: T("已取消", "Canceled"), level: .neutral)
        case .none:
            return StatusBadge(text: T("待验证", "Not verified"), level: .neutral)
        }
    }
}
