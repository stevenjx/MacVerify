// Views/CameraTestView.swift
//
// 摄像头测试：真实打开摄像头预览。显示的分辨率取自当前激活的采集格式，
// 不是写死的「1080p」，也不是从机型推出来的。
import SwiftUI
import AVFoundation
import AVKit
import AppKit

@MainActor
final class CameraTestModel: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published var permissionDenied = false
    @Published var noCamera = false
    @Published var isRunning = false
    @Published var deviceName = ""
    @Published var resolution = ""
    @Published var errorText: String?

    let session = AVCaptureSession()
    private var device: AVCaptureDevice?

    /// 录像：直接写到桌面，文件名带时间戳，避免覆盖
    private let movieOutput = AVCaptureMovieFileOutput()
    @Published var isRecording = false
    @Published var recordedSeconds: Double = 0
    @Published var savedURL: URL?
    @Published var saveError: String?
    private var recordStartedAt: Date?
    private var ticker: Timer?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self = self else { return }
                    if granted { self.configure() } else { self.permissionDenied = true }
                }
            }
        default:
            permissionDenied = true
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            noCamera = true
            return
        }
        deviceName = device.localizedName
        self.device = device

        session.beginConfiguration()
        session.sessionPreset = .high
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            errorText = T("无法读取摄像头输入", "Couldn't open the camera input")
            return
        }
        session.addInput(input)
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        session.commitConfiguration()

        nonisolated(unsafe) let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = true
                // 采集分辨率必须在会话跑起来之后读：preset 会在 start 时改写 activeFormat
                self?.refreshFormat()
            }
        }
    }

    private func refreshFormat() {
        guard let device = device else { return }
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        resolution = dimensions.width > 0 ? "\(dimensions.width) × \(dimensions.height)" : "—"
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
        isRunning = false
    }

    // MARK: 录制

    func startRecording() {
        guard !isRecording, session.isRunning, session.outputs.contains(movieOutput) else { return }
        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            saveError = T("找不到桌面目录，无法保存录像。", "The Desktop folder could not be located.")
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = desktop.appendingPathComponent("MacVerify-Camera-\(formatter.string(from: Date())).mov")

        savedURL = nil
        saveError = nil
        recordedSeconds = 0
        recordStartedAt = Date()
        isRecording = true
        movieOutput.startRecording(to: url, recordingDelegate: self)

        ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let start = self.recordStartedAt else { return }
                self.recordedSeconds = Date().timeIntervalSince(start)
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        Task { @MainActor in
            self.isRecording = false
            self.ticker?.invalidate()
            self.ticker = nil
            self.recordStartedAt = nil
            if let error = error {
                // 写桌面可能被「文件与文件夹」隐私设置拦下，如实说明并给出路径
                self.saveError = T("录像没有保存成功：\(error.localizedDescription)",
                                   "The recording could not be saved: \(error.localizedDescription)")
            } else {
                self.savedURL = outputFileURL
            }
        }
    }

    func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// AVCaptureVideoPreviewLayer 的 SwiftUI 包装
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspect
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = preview
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct CameraTestView: View {
    @StateObject private var model = CameraTestModel()
    @State private var showPlayer = false

    var body: some View {
        PageScroll {
            PageHeader(
                title: T("摄像头", "Camera"),
                subtitle: T("看画面是否清晰、有无坏点或偏色", "Check for clarity, dead pixels and colour cast")
            )

            Card(title: T("实时预览", "Live preview"), icon: "camera",
                 trailing: AnyView(
                    StatusBadge(text: model.isRunning ? T("采集中", "Capturing") : T("未开始", "Idle"),
                                level: model.isRunning ? .ok : .neutral)
                 )) {
                VStack(alignment: .leading, spacing: Space.md) {
                    if model.permissionDenied {
                        NoticeBar(text: T("摄像头权限未开启。请在「系统设置 › 隐私与安全性 › 摄像头」中允许 MacVerify，然后重新打开本页。",
                                          "Camera access is off. Allow MacVerify in System Settings › Privacy & Security › Camera, then reopen this page."),
                                  level: .warning)
                        SecondaryButton(title: T("打开摄像头权限设置", "Open Camera Settings"), icon: "gearshape") {
                            model.openCameraSettings()
                        }
                    } else if model.noCamera {
                        NoticeBar(text: T("本机没有检测到摄像头。", "No camera detected on this Mac."), level: .warning)
                    } else {
                        CameraPreview(session: model.session)
                            .frame(height: 320)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                    .stroke(Surface.border, lineWidth: 1)
                            )

                        FactGrid(facts: [
                            Fact(T("设备", "Device"), model.deviceName.isEmpty ? "—" : model.deviceName),
                            Fact(T("采集分辨率", "Capture size"), model.resolution.isEmpty ? "—" : model.resolution)
                        ], columns: 2, labelWidth: 80)

                        recordingControls

                        if let error = model.errorText {
                            NoticeBar(text: error, level: .warning)
                        }
                        if let error = model.saveError {
                            NoticeBar(text: error, level: .warning)
                        }
                    }
                }
            }

            NoticeBar(text: T("预览不会录制；只有点「录制视频」才会把 .mov 写到桌面。离开本页会自动停止录制并释放摄像头。",
                              "Preview alone records nothing; only the Record button writes a .mov to the Desktop. Leaving the page stops recording and releases the camera."),
                      level: .neutral)
        }
        .onAppear { model.start() }
        .onDisappear {
            if model.isRecording { model.stopRecording() }
            model.stop()
        }
        .onChange(of: model.isRunning) { running in
            // 采集会话真的跑起来、分辨率也读到了，才算这台机器的摄像头可用
            if running { TestProgress.shared.markCompleted("camera") }
        }
    }
    // MARK: - 录制

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                if model.isRecording {
                    StatusDot(level: .critical, size: 7)
                    Text(T("录制中 \(timeText(model.recordedSeconds))",
                           "Recording \(timeText(model.recordedSeconds))"))
                        .font(Typo.body)
                    Spacer(minLength: 0)
                    SecondaryButton(title: T("停止录制", "Stop"), icon: "stop.fill") {
                        model.stopRecording()
                    }
                } else {
                    PrimaryButton(title: T("录制视频", "Record video"),
                                  icon: "record.circle",
                                  enabled: model.isRunning) {
                        model.startRecording()
                    }
                    if let url = model.savedURL {
                        SecondaryButton(title: showPlayer ? T("收起回放", "Hide player") : T("回放", "Play back"),
                                        icon: showPlayer ? "chevron.up" : "play.fill") {
                            showPlayer.toggle()
                        }
                        Text(T("已保存到桌面：\(url.lastPathComponent)",
                               "Saved to the Desktop: \(url.lastPathComponent)"))
                            .font(Typo.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(T("录像以 .mov 保存到桌面，文件名带时间戳；不录音、不上传。",
                               "Recordings are saved to the Desktop as .mov with a timestamp; no audio, nothing uploaded."))
                            .font(Typo.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if showPlayer, let url = model.savedURL {
                VideoPlayerView(url: url)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .stroke(Surface.border, lineWidth: 1)
                    )
            }
        }
    }

    private func timeText(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

}

/// AVPlayerView 的 SwiftUI 包装：带播放/暂停与进度条，不自动播放。
struct VideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = AVPlayer(url: url)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        guard let item = nsView.player?.currentItem else {
            nsView.player = AVPlayer(url: url)
            return
        }
        if (item.asset as? AVURLAsset)?.url != url {
            nsView.player?.pause()
            nsView.player = AVPlayer(url: url)
        }
    }
}
