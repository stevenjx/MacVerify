// Views/AudioTestView.swift
//
// 音频测试：扬声器扫频 + 麦克风录音回放。
// 播放的是程序生成的对数扫频（100 Hz → 16 kHz），不是内置音乐文件：
// 扫频覆盖整个可听频段，破音、共振、杂音在扫过对应频率时会暴露得比任何一首歌都清楚，
// 而商业音乐涉及版权，不能随 App 分发。
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
}

@MainActor
final class SpeakerTestModel: ObservableObject {
    @Published var channel: PlayChannel = .both
    @Published var playing: PlayChannel? = nil
    @Published var errorText: String?
    /// 已经播过的声道（0 左 / 1 右）。左右都过一遍才算测完。
    @Published var playedChannels: Set<Int> = []

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var prepared = false

    func play() {
        guard let buffer = Self.sweep(channel: channel) else {
            errorText = T("无法生成测试音", "Couldn't create the test tone")
            return
        }
        if !prepared {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            do {
                try engine.start()
                prepared = true
            } catch {
                errorText = T("音频输出启动失败：\(error.localizedDescription)",
                              "Couldn't start audio output: \(error.localizedDescription)")
                return
            }
        }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        playing = channel
        switch channel {
        case .left: playedChannels.insert(0)
        case .right: playedChannels.insert(1)
        case .both: playedChannels.formUnion([0, 1])
        }
        errorText = nil
    }

    func stop() {
        player.stop()
        playing = nil
    }

    func teardown() {
        stop()
        if prepared { engine.stop() }
    }

    /// 8 秒对数扫频，两端各 20 ms 淡入淡出，避免起止爆音被误当成扬声器故障。
    private static func sweep(channel: PlayChannel) -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        let duration = 8.0
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return nil }
        buffer.frameLength = frames

        let f0 = 100.0
        let f1 = 16_000.0
        let ratio = f1 / f0
        let fade = 0.02

        for frame in 0..<Int(frames) {
            let t = Double(frame) / sampleRate
            let phase = 2 * Double.pi * f0 * duration / log(ratio) * (pow(ratio, t / duration) - 1)
            var amplitude = 0.28
            if t < fade { amplitude *= t / fade }
            if t > duration - fade { amplitude *= (duration - t) / fade }
            let value = Float(sin(phase) * amplitude)
            buffer.floatChannelData?[0][frame] = (channel == .right) ? 0 : value
            buffer.floatChannelData?[1][frame] = (channel == .left) ? 0 : value
        }
        return buffer
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
                subtitle: T("扫频测扬声器，录音回放测麦克风", "Sweep for the speakers, record and play back for the microphone")
            )

            speakerCard
            microphoneCard

            NoticeBar(text: T("扫频音会从 100 Hz 扫到 16 kHz：低频听有没有嗡嗡共振，高频听有没有破音和杂音。整个过程不保存任何音频到磁盘。",
                              "The sweep runs from 100 Hz to 16 kHz: listen for rattle at the low end and crackle at the top. Nothing is written to disk."),
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
                    Fact(T("输出设备", "Output"), outputName),
                    Fact(T("测试信号", "Test signal"), T("扫频 100 Hz – 16 kHz · 8 s 循环",
                                                        "Sweep 100 Hz – 16 kHz, 8 s loop"))
                ], columns: 2, labelWidth: 72)

                HStack(spacing: Space.md) {
                    SegmentedPicker(options: PlayChannel.allCases,
                                    title: { $0.title },
                                    selection: $speaker.channel,
                                    enabled: speaker.playing == nil)
                    SecondaryButton(title: T("停止", "Stop"), icon: "stop.fill") {
                        speaker.stop()
                    }
                }

                HStack(spacing: Space.sm) {
                    PrimaryButton(title: speaker.playing == nil
                                  ? T("播放测试音", "Play test tone")
                                  : T("播放中…", "Playing…"),
                                  icon: "play.fill",
                                  enabled: speaker.playing == nil) {
                        speaker.play()
                    }
                    Text(T("只有选中的声道会响；双声道时两侧同时响。",
                           "Only the selected channel sounds; Both plays them together."))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                }

                if let error = speaker.errorText {
                    NoticeBar(text: error, level: .warning)
                }
            }
        }
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
