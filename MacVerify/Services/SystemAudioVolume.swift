// Services/SystemAudioVolume.swift
//
// 系统输出音量：读默认输出设备的音量与静音状态，也让测试页直接改它。
//
// 为什么不用 App 自己的增益滑块：验机时要判断的是「这台机器的喇叭在正常音量下有没有破音」，
// 如果只调 App 播放增益，系统音量仍为 0 时照样没声音，只会让人误判喇叭坏了。
//
// 取值的顺序（不同设备暴露的属性不一样）：
//   1. kAudioHardwareServiceDeviceProperty_VirtualMainVolume —— 内建喇叭、多数 USB 声卡
//   2. kAudioDevicePropertyVolumeScalar（主元素）—— 部分设备只有主音量
//   3. 左右声道各自音量取平均 —— 只有分声道属性的设备
import CoreAudio
import Foundation

enum SystemAudioVolume {

    static func current() -> Float? {
        guard let device = defaultOutputDevice() else { return nil }
        if let value = scalar(device: device, selector: virtualMainVolume, element: mainElement) {
            return value
        }
        if let value = scalar(device: device, selector: kAudioDevicePropertyVolumeScalar, element: mainElement) {
            return value
        }
        let left = scalar(device: device, selector: kAudioDevicePropertyVolumeScalar, element: 1)
        let right = scalar(device: device, selector: kAudioDevicePropertyVolumeScalar, element: 2)
        switch (left, right) {
        case let (l?, r?): return (l + r) / 2
        case let (l?, nil): return l
        case let (nil, r?): return r
        default: return nil
        }
    }

    /// 设置音量（0…1）。设置成功返回 true。
    @discardableResult
    static func set(_ value: Float) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        let clamped = min(max(value, 0), 1)

        if writeScalar(device: device, selector: virtualMainVolume, element: mainElement, value: clamped) {
            return true
        }
        if writeScalar(device: device, selector: kAudioDevicePropertyVolumeScalar, element: mainElement, value: clamped) {
            return true
        }
        let left = writeScalar(device: device, selector: kAudioDevicePropertyVolumeScalar, element: 1, value: clamped)
        let right = writeScalar(device: device, selector: kAudioDevicePropertyVolumeScalar, element: 2, value: clamped)
        return left || right
    }

    static func isMuted() -> Bool? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: mainElement)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    @discardableResult
    static func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: mainElement)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }

    // MARK: - 底层

    /// macOS 12 起主元素就是这个常量；旧名字 Master 只是别名
    private static let mainElement = kAudioObjectPropertyElementMain

    /// 'vmvc'，见 AudioHardware.h
    private static let virtualMainVolume = AudioObjectPropertySelector(0x766D_7663)

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: mainElement)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                                &address, 0, nil, &size, &device)
        guard status == noErr, device != 0 else { return nil }
        return device
    }

    private static func scalar(device: AudioDeviceID,
                               selector: AudioObjectPropertySelector,
                               element: AudioObjectPropertyElement) -> Float? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: element)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func writeScalar(device: AudioDeviceID,
                                    selector: AudioObjectPropertySelector,
                                    element: AudioObjectPropertyElement,
                                    value: Float) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeOutput,
                                                 mElement: element)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var scalar = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &scalar) == noErr
    }
}
