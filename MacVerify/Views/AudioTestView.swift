// Views/AudioTestView.swift
//
// 音频测试：扬声器/耳机左右声道 + 麦克风电平。
// 播放的是真实正弦波（440 Hz），麦克风电平由实际采到的样本算 RMS，不做假动画。
import SwiftUI
import AVFoundation
import AppKit

// MARK: - 播放

@MainActor
final class SpeakerTestModel: ObservableObject {
    /// 0 = 左声道, 1 = 右声道, nil = 停止
    @Published var playing: Int? = nil
    @Published var errorText: String?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var prepared = false

    func play(channel: Int) {
        guard let buffer = Self.tone(channel: channel) else {
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

    /// 单声道正弦波：另一侧保持静音，才能分辨左右。
    private static func tone(channel: Int) -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        let frames = AVAudioFrameCount(sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return nil }
        buffer.frameLength = frames
        for frame in 0..<Int(frames) {
            let value = Float(sin(2.0 * Double.pi * 440.0 * Double(frame) / sampleRate)) * 0.25
            buffer.floatChannelData?[0][frame] = channel == 0 ? value : 0
            buffer.floatChannelData?[1][frame] = channel == 1 ? value : 0
        }
        return buffer
    }
}

// MARK: - 录音

@MainActor
final class MicrophoneTestModel: ObservableObject {
    @Published var level: Double = 0
    @Published var peak: Double = 0
    @Published var isRunning = false
    @Published var permissionDenied = false
    @Published var errorText: String?

    private let engine = AVAudioEngine()

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

    /// 音频线程上算 RMS，返回 0...1
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
                subtitle: T("左右声道各播一次，再对着麦克风说话看电平", "Play each channel, then speak and watch the level")
            )

            Card(title: T("扬声器 / 耳机", "Speaker / Headphones"), icon: "speaker.wave.2") {
                VStack(alignment: .leading, spacing: Space.md) {
                    FactGrid(facts: [
                        Fact(T("输出设备", "Output"), outputName),
                        Fact(T("测试音", "Tone"), "440 Hz · 1 s")
                    ], columns: 2, labelWidth: 72)

                    HStack(spacing: Space.sm) {
                        channelButton(T("左声道", "Left"), channel: 0, icon: "l.circle.fill")
                        channelButton(T("右声道", "Right"), channel: 1, icon: "r.circle.fill")
                        SecondaryButton(title: T("停止", "Stop"), icon: "stop.fill") {
                            speaker.stop()
                        }
                    }

                    Text(T("只有对应一侧会响：左声道响右声道静音，反之亦然。插入耳机可同时验证耳机口。",
                           "Only the chosen side should sound; the other stays silent. Plugging in headphones also tests the jack."))
                        .font(Typo.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let error = speaker.errorText {
                        NoticeBar(text: error, level: .warning)
                    }
                }
            }

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
                        Text(microphone.isRunning
                             ? T("正在监听：说话时电平条应随之变化", "Listening — the bar should move when you speak")
                             : T("未在监听", "Not listening"))
                            .font(Typo.caption)
                            .foregroundColor(.secondary)
                    }

                    if let error = microphone.errorText {
                        NoticeBar(text: error, level: .warning)
                    }
                }
            }

            NoticeBar(text: T("播放与录音都使用本机音频接口，不保存任何录音；离开本页会自动停止。",
                              "Playback and recording use the local audio device only. Nothing is saved, and both stop when you leave this page."),
                      level: .neutral)
        }
        .onDisappear {
            speaker.teardown()
            microphone.stop()
        }
        .onAppear { microphone.start() }
    }

    private func channelButton(_ title: String, channel: Int, icon: String) -> some View {
        Button {
            speaker.play(channel: channel)
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.borderedProminent)
        .tint(speaker.playing == channel ? Color.accentColor : Color.gray)
        .controlSize(.large)
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
}
