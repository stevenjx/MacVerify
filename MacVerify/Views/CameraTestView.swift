// Views/CameraTestView.swift
//
// 摄像头测试：真实打开摄像头预览。显示的分辨率取自当前激活的采集格式，
// 不是写死的「1080p」，也不是从机型推出来的。
import SwiftUI
import AVFoundation
import AppKit

@MainActor
final class CameraTestModel: ObservableObject {
    @Published var permissionDenied = false
    @Published var noCamera = false
    @Published var isRunning = false
    @Published var deviceName = ""
    @Published var resolution = ""
    @Published var errorText: String?

    let session = AVCaptureSession()
    private var device: AVCaptureDevice?

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

                        if let error = model.errorText {
                            NoticeBar(text: error, level: .warning)
                        }
                    }
                }
            }

            NoticeBar(text: T("画面只在本机显示，不录制、不保存。离开本页会立即释放摄像头。",
                              "The preview stays on this Mac: nothing is recorded or saved, and the camera is released when you leave."),
                      level: .neutral)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}
