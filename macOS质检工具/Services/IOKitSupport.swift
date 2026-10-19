// Services/IOKitSupport.swift
import Foundation
import IOKit

enum IOKit {
    /// 读取 IORegistry 条目的单个属性
    static func property(_ service: io_object_t, _ key: String) -> Any? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return value.takeRetainedValue()
    }

    /// 读取条目的全部属性
    static func properties(_ service: io_object_t) -> [String: Any] {
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    /// 遍历匹配的 IOService
    static func forEachService(matching className: String, _ body: (io_object_t) -> Void) {
        guard let matching = IOServiceMatching(className) else { return }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(0, matching, &iterator) == kIOReturnSuccess else { return }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            body(service)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    static func firstService(matching className: String) -> io_object_t {
        guard let matching = IOServiceMatching(className) else { return 0 }
        return IOServiceGetMatchingService(0, matching)
    }
}

enum Sysctl {
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func int(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    static func int32(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}

enum Shell {
    /// 执行只读命令并返回标准输出（失败返回 nil）
    @discardableResult
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 4) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        let semaphore = DispatchSemaphore(value: 0)
        var output = Data()

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                output.append(chunk)
            }
        }

        process.terminationHandler = { _ in semaphore.signal() }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            pipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        pipe.fileHandleForReading.readabilityHandler = nil
        guard process.terminationStatus == 0 else { return nil }
        return String(data: output, encoding: .utf8)
    }
}
