// Views/AudioTestView.swift
//
// 音频测试：扬声器播放内置音乐 + 麦克风录音回放。
// 音乐来自 App 内置的 test.mp3，循环播放；可选择左 / 右 / 双声道（播放中切换即时生效），
// 音量滑块直接改系统输出音量——验机时要判断的是「这台机器在正常音量下有没有破音」，
// 只调 App 自己的增益，系统音量为 0 时照样没声音，容易误判。
import SwiftUI
import AVFoundation
import AppKit

// MARK: - 播放

enum PlayChannel: Int, CaseIterable, Identifiable, Hashable {
    case left = 0
    case right = 1
    case both = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .left: return T("左声道", "Left")
        case .right: return T("右声道", "Right")
        case .both: return T("双声道", "Both")
        }
    }

    /// 传给 AVAudioPlayer.pan：-1 全左、+1 全右、0 居中。
    /// 对立体声文件而言 pan 是左右平衡，因此 -1 时右声道完全不响，正是「测某一边」要的效果。
    var pan: Float {
        switch self {
        case .left: return -1
        case .right: return 1
        case .both: return 0
        }
    }
}

@MainActor
final class SpeakerTestModel: ObservableObject {
    /// 播放中切换声道即时生效：改 pan 即可，不必重新开始
    @Published var channel: PlayChannel = .both {
        didSet {
            player?.pan = channel.pan
            if playing { recordPlayed(channel) }
        }
    }
    @Published private(set) var playing = false
    @Published private(set) var elapsed: Double = 0
    @Published var errorText: String?
    /// 已经播过的声道（0 左 / 1 右）。左右都过一遍才算测完。
    @Published private(set) var playedChannels: Set<Int> = []

    /// 系统输出音量 0…1
    @Published private(set) var volume: Double = 0
    @Published private(set) var isMuted = false
    /// 输出设备是否提供音量控制（HDMI、部分外置 DAC 不提供）
    @Published private(set) var canControlVolume = true

    /// 内置音乐的时长；0 表示没取到文件
    let duration: Double

    private var player: AVAudioPlayer?
    private var ticker: Timer?

    private static let resourceName = "test"
    private static let resourceExtension = "mp3"

    static var trackURL: URL? {
        Bundle.main.url(forResource: resourceName, withExtension: resourceExtension)
    }

    init() {
        duration = Self.trackURL
            .flatMap { try? AVAudioPlayer(contentsOf: $0) }
            .map(\.duration) ?? 0
        refreshVolume()
    }

    // MARK: - 音量

    func refreshVolume() {
        if let value = SystemAudioVolume.current() {
            volume = Double(value)
            canControlVolume = true
        } else {
            canControlVolume = false
        }
        isMuted = SystemAudioVolume.isMuted() ?? false
    }

    /// 滑块直接改系统输出音量；静音状态下拖动会自动取消静音
    func setVolume(_ value: Double) {
        volume = min(max(value, 0), 1)
        guard canControlVolume else { return }
        guard SystemAudioVolume.set(Float(volume)) else {
            canControlVolume = false
            return
        }
        if isMuted, SystemAudioVolume.setMuted(false) {
            isMuted = false
        }
    }

    func toggleMute() {
        let target = !isMuted
        if SystemAudioVolume.setMuted(target) {
            isMuted = target
        }
    }

    // MARK: - 播放

    func play() {
        guard let url = Self.trackURL else {
            errorText = T("内置测试音乐缺失（test.mp3），无法播放。",
                          "The bundled test track (test.mp3) is missing.")
            return
        }
        if player == nil {
            do {
                let audio = try AVAudioPlayer(contentsOf: url)
                audio.numberOfLoops = -1      // 单曲循环，够听完两侧
                audio.prepareToPlay()
                player = audio
            } catch {
                errorText = T("无法打开测试音乐：\(error.localizedDescription)",
                              "Couldn't open the test track: \(error.localizedDescription)")
                return
            }
        }

        // 系统静音时播放会得出「喇叭坏了」的错误结论，先取消静音
        if SystemAudioVolume.isMuted() == true, SystemAudioVolume.setMuted(false) {
            isMuted = false
        }

        player?.pan = channel.pan
        player?.currentTime = 0
        guard player?.play() == true else {
            errorText = T("音频输出启动失败，请检查输出设备。",
                          "Couldn't start audio output — check the output device.")
            return
        }
        playing = true
        elapsed = 0
        recordPlayed(channel)
        refreshVolume()
        startTicker()
        errorText = nil
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        playing = false
        elapsed = 0
        stopTicker()
    }

    func teardown() {
        stop()
        player = nil
    }

    private func recordPlayed(_ channel: PlayChannel) {
        switch channel {
        case .left: playedChannels.insert(0)
        case .right: playedChannels.insert(1)
        case .both: playedChannels.formUnion([0, 1])
        }
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.player else { return }
                self.elapsed = player.currentTime
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

// MARK: - 录音与回放

@MainActor
final class MicrophoneTestModel: ObservableObject {
    @Published var level: Double = 0
    @Published var peak: Double = 0
    @Published var isRunning = false
    @Published var permissionDenied = false
    @Published var errorText: String?
    @Published var hasSignal = false

    @Published var isRecording = false
    @Published var recordSeconds: Double = 0
    @Published var recordedURL: URL?
    @Published var isPlayingBack = false

    private let engine = AVAudioEngine()
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var ticker: Timer?

    // MARK: 监听

    func start() {
        guard !isRunning else { return }
        permissionDenied = false
        errorText = nil

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginTap()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self = self else { return }
                    if granted { self.beginTap() } else { self.permissionDenied = true }
                }
            }
        default:
            permissionDenied = true
        }
    }

    private func beginTap() {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            errorText = T("未检测到可用的麦克风输入设备。", "No microphone input device found.")
            return
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let value = MicrophoneTestModel.rms(buffer)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.level = value
                self.peak = max(self.peak * 0.92, value)
                if value > 0.05 { self.hasSignal = true }
            }
        }
        do {
            engine.prepare()
            try engine.start()
            isRunning = true
        } catch {
            input.removeTap(onBus: 0)
            errorText = T("麦克风监听启动失败：\(error.localizedDescription)",
                          "Couldn't start the microphone: \(error.localizedDescription)")
        }
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<frames { sum += channel[index] * channel[index] }
        return min(1, Double(sqrt(sum / Float(frames))) * 8)
    }

    func stop() {
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            isRunning = false
        }
        level = 0
    }

    // MARK: 录音

    func startRecording() {
        guard !isRecording else { return }
        // 录音与实时监听不能同时抓同一个输入节点，先停监听
        stop()
        stopPlayback()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacVerify-mic-\(Int(Date().timeIntervalSince1970)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record()
            self.recorder = recorder
            recordedURL = nil
            recordSeconds = 0
            isRecording = true
            ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, let recorder = self.recorder else { return }
                    self.recordSeconds = recorder.currentTime
                }
            }
        } catch {
            errorText = T("无法开始录音：\(error.localizedDescription)",
                          "Couldn't start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        ticker?.invalidate()
        ticker = nil
        recorder?.stop()
        recordedURL = recorder?.url
        recorder = nil
        isRecording = false
        // 录完回到监听状态，方便继续看电平
        start()
    }

    // MARK: 回放

    func playRecording() {
        guard let url = recordedURL else { return }
        stopPlayback()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            self.player = player
            isPlayingBack = true
            ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, let player = self.player else { return }
                    if !player.isPlaying {
                        self.isPlayingBack = false
                        self.ticker?.invalidate()
                        self.ticker = nil
                    }
                }
            }
        } catch {
            errorText = T("无法回放：\(error.localizedDescription)",
                          "Couldn't play the recording: \(error.localizedDescription)")
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlayingBack = false
        ticker?.invalidate()
        ticker = nil
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - 页面

struct AudioTestView: View {
    @EnvironmentObject private var system: SystemInfoStore
    @StateObject private var speaker = SpeakerTestModel()
    @StateObject private var microphone = MicrophoneTestModel()

    private var outputName: String {
        system.info.peripherals.builtinSpeaker?.name ?? T("系统默认输出", "System default output")
    }

    private var inputName: String {
        system.info.peripherals.builtinMicrophone?.name ?? T("系统默认输入", "System default input")
    }

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("扬声器与麦克风", "Speakers & Microphone"),
                subtitle: T("播放内置音乐测扬声器，录音回放测麦克风", "Bundled music for the speakers, record and play back for the microphone")
            )

            speakerCard
            microphoneCard

            NoticeBar(text: T("音乐循环播放，可随时切换左 / 右声道确认两侧都能出声；音量滑块直接改系统输出音量。播放不写任何文件到磁盘。",
                              "The track loops; switch left and right at any time to confirm both sides sound. The volume slider changes the system output volume. Nothing is written to disk."),
                      level: .neutral)
        }
        .onDisappear {
            speaker.teardown()
            microphone.stop()
            microphone.stopPlayback()
        }
        .onAppear { microphone.start() }
        .onChange(of: isComplete) { done in
            if done { TestProgress.shared.markCompleted("audio") }
        }
    }

    // MARK: - 扬声器

    private var speakerCard: some View {
        Card(title: T("扬声器 / 耳机", "Speaker / Headphones"), icon: "speaker.wave.2") {
            VStack(alignment: .leading, spacing: Space.md) {
                FactGrid(facts: [
                    Fact(T("输出设备", "Output"), outputName)
                ], columns: 1, labelWidth: 72)

                HStack(spacing: Space.sm) {
                    rowLabel(T("声道", "Channel"))
                    SegmentedPicker(options: PlayChannel.allCases,
                                    title: { $0.title },
                                    selection: $speaker.channel,
                                    enabled: true)
                    Spacer(minLength: 0)
                    Text(T("播放中可随时切换", "Switch anytime while playing"))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: Space.sm) {
                    rowLabel(T("音量", "Volume"))
                    Button(action: { speaker.toggleMute() }) {
                        Image(systemName: speaker.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(Typo.icon(11, weight: .semibold))
                            .foregroundColor(speaker.isMuted ? StatusPalette.warning : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(speaker.isMuted ? T("取消静音", "Unmute") : T("静音", "Mute"))

                    Slider(value: Binding(get: { speaker.volume },
                                          set: { speaker.setVolume($0) }),
                           in: 0...1)
                        .frame(width: 190)
                        .disabled(!speaker.canControlVolume)

                    Text("\(Int(speaker.volume * 100))%")
                        .font(Typo.mono)
                        .foregroundColor(.secondary)
                        .frame(width: 34, alignment: .trailing)

                    if speaker.isMuted {
                        StatusBadge(text: T("已静音", "Muted"), level: .warning)
                    }
                    if !speaker.canControlVolume {
                        Text(T("此输出设备不提供音量控制，请调节设备本身。",
                               "This output has no volume control; adjust the device itself."))
                            .font(Typo.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: Space.sm) {
                    PrimaryButton(title: speaker.playing
                                  ? T("播放中…", "Playing…")
                                  : T("播放音乐", "Play music"),
                                  icon: "play.fill",
                                  enabled: !speaker.playing) {
                        speaker.play()
                    }
                    SecondaryButton(title: T("停止", "Stop"), icon: "stop.fill",
                                    enabled: speaker.playing) {
                        speaker.stop()
                    }
                    if speaker.playing {
                        Text("\(timeText(speaker.elapsed)) / \(timeText(speaker.duration))")
                            .font(Typo.mono)
                            .foregroundColor(.secondary)
                    }
                    Text(T("只有选中的声道会响；双声道时两侧同时响。",
                           "Only the selected channel sounds; Both plays them together."))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                }

                if let error = speaker.errorText {
                    NoticeBar(text: error, level: .warning)
                }
            }
        }
    }

    /// 与 FactGrid 的标签列对齐（labelWidth 72）
    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(Typo.caption)
            .foregroundColor(.secondary)
            .frame(width: 72, alignment: .leading)
    }

    // MARK: - 麦克风

    private var microphoneCard: some View {
        Card(title: T("麦克风", "Microphone"), icon: "mic") {
            VStack(alignment: .leading, spacing: Space.md) {
                FactGrid(facts: [
                    Fact(T("输入设备", "Input"), inputName)
                ], columns: 1, labelWidth: 72)

                if microphone.permissionDenied {
                    NoticeBar(text: T("麦克风权限未开启。请在「系统设置 › 隐私与安全性 › 麦克风」中允许 MacVerify，然后重新打开本页。",
                                      "Microphone access is off. Allow MacVerify in System Settings › Privacy & Security › Microphone, then reopen this page."),
                              level: .warning)
                    SecondaryButton(title: T("打开麦克风权限设置", "Open Microphone Settings"), icon: "gearshape") {
                        microphone.openMicrophoneSettings()
                    }
                } else {
                    levelBar(value: microphone.level, peak: microphone.peak)

                    if microphone.isRecording {
                        HStack(spacing: Space.sm) {
                            StatusDot(level: .critical, size: 7)
                            Text(T("录音中 \(timeText(microphone.recordSeconds))",
                                   "Recording \(timeText(microphone.recordSeconds))"))
                                .font(Typo.body)
                            Spacer(minLength: 0)
                            SecondaryButton(title: T("停止录音", "Stop"), icon: "stop.fill") {
                                microphone.stopRecording()
                            }
                        }
                    } else {
                        HStack(spacing: Space.sm) {
                            PrimaryButton(title: T("开始录音", "Record"), icon: "record.circle") {
                                microphone.startRecording()
                            }
                            if microphone.recordedURL != nil {
                                SecondaryButton(title: microphone.isPlayingBack
                                                ? T("停止回放", "Stop playback") : T("回放录音", "Play back"),
                                                icon: microphone.isPlayingBack ? "stop.fill" : "play.fill") {
                                    if microphone.isPlayingBack {
                                        microphone.stopPlayback()
                                    } else {
                                        microphone.playRecording()
                                    }
                                }
                                Text(T("已录制 \(recordingLength)，可直接回放",
                                       "Recorded \(recordingLength) — play it back"))
                                    .font(Typo.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(T("录音只用于回放确认拾音质量，退出 App 即清理。",
                                       "The recording only exists for playback and is discarded when the app quits."))
                                    .font(Typo.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if let error = microphone.errorText {
                        NoticeBar(text: error, level: .warning)
                    }
                }
            }
        }
    }

    private func levelBar(value: Double, peak: Double) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Surface.well)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(StatusPalette.ok)
                        .frame(width: geometry.size.width * CGFloat(min(max(value, 0), 1)))
                }
            }
            .frame(height: 18)

            Text(T("峰值 \(Int(peak * 100))%", "Peak \(Int(peak * 100))%"))
                .font(Typo.caption)
                .foregroundColor(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(T("麦克风电平 \(Int(value * 100))%", "Microphone level \(Int(value * 100))%"))
    }

    private func timeText(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private var recordingLength: String {
        guard let url = microphone.recordedURL else { return "0:00" }
        return timeText((try? AVAudioPlayer(contentsOf: url))?.duration ?? 0)
    }

    /// 左右声道都播过、且麦克风真的拾到过声音 —— 两项都成立才算测完
    private var isComplete: Bool {
        speaker.playedChannels.count == 2 && microphone.hasSignal
    }
}
