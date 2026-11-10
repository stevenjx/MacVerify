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
}

enum Shell {
    /// 执行只读命令并返回标准输出（失败或输出为空返回 nil）
    ///
    /// 三个必须处理的实际问题：
    /// 1. stderr 必须接管。原先 `process.standardError = Pipe()` 但从不读取，
    ///    子进程写满 64KB 管道缓冲后会永久阻塞，只能等超时。
    /// 2. 必须读到 EOF。原先用 terminationHandler 就返回，进程退出瞬间管道里
    ///    残留的数据会丢失，`system_profiler -json` 会变成被截断的非法 JSON。
    /// 3. 超时后 terminate 并回收，避免留下子进程。
    @discardableResult
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 4) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.qualityOfService = .userInitiated

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        let outputLock = NSLock()
        var output = Data()

        do {
            try process.run()
        } catch {
            return nil
        }
        // 关键：父进程必须关掉自己持有的写端，否则读端永远等不到 EOF，
        // 只能靠超时兜底，最后还会在 Process 释放时崩溃（task still running）。
        stdout.fileHandleForWriting.closeFile()

        // 独立线程读到 EOF，保证输出完整
        let reader = Thread {
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            outputLock.lock()
            output = data
            outputLock.unlock()
            finished.signal()
        }
        reader.stackSize = 128 * 1024
        reader.start()

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 0.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        // 确保进程确实结束，否则 Process 释放时会抛 "task still running"
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        outputLock.lock()
        let data = output
        outputLock.unlock()

        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
