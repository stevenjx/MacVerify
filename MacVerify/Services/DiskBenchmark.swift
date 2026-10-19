// Services/DiskBenchmark.swift
import Foundation
import Combine
import Darwin

enum BenchmarkPhase {
    case idle
    case preparing
    case writing
    case reading
    case finished
    case failed
}

final class DiskBenchmark: ObservableObject {
    @Published private(set) var phase: BenchmarkPhase = .idle
    @Published private(set) var writeSpeed: Double = 0
    @Published private(set) var readSpeed: Double = 0
    @Published private(set) var progress: Double = 0
    @Published private(set) var message: String = T("就绪", "Ready")
    @Published private(set) var isRunning = false

    private let queue = DispatchQueue(label: "macverify.disk.benchmark", qos: .userInitiated)
    private let cancelLock = NSLock()
    private var cancelled = false

    private let chunkSize = 8 * 1024 * 1024

    func start(sizeMB: Int) {
        guard !isRunning else { return }
        cancelLock.lock()
        cancelled = false
        cancelLock.unlock()

        isRunning = true
        phase = .preparing
        progress = 0
        writeSpeed = 0
        readSpeed = 0
        message = T("正在准备测试文件…", "Preparing test file…")

        queue.async { [weak self] in
            self?.run(sizeMB: sizeMB)
        }
    }

    func cancel() {
        cancelLock.lock()
        cancelled = true
        cancelLock.unlock()
    }

    private var isCancelled: Bool {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        return cancelled
    }

    private func run(sizeMB: Int) {
        let totalBytes = sizeMB * 1024 * 1024
        let chunkCount = max(1, totalBytes / chunkSize)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macverify-benchmark-\(UUID().uuidString).bin")

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        guard FileManager.default.createFile(atPath: fileURL.path, contents: nil) else {
            finish(phase: .failed, message: T("无法创建测试文件", "Unable to create test file"))
            return
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            finish(phase: .failed, message: T("无法打开测试文件", "Unable to open test file"))
            return
        }

        // 真实随机数据，避免被主控透明压缩
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        arc4random_buf(&buffer, chunkSize)
        let payload = Data(bytes: buffer, count: chunkSize)

        _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1)

        publish { $0.phase = .writing }

        var written = 0
        let writeStart = DispatchTime.now().uptimeNanoseconds

        for index in 0..<chunkCount {
            if isCancelled { break }
            do {
                try handle.write(contentsOf: payload)
                written += chunkSize
            } catch {
                break
            }

            let elapsed = seconds(since: writeStart)
            let speed = Double(written) / 1_048_576 / max(elapsed, 0.001)
            publish { state in
                state.writeSpeed = speed
                state.progress = Double(index + 1) / Double(chunkCount) * 0.5
                state.message = T("写入 \(index + 1)/\(chunkCount) · \(Int(speed)) MB/s",
                                  "Writing \(index + 1)/\(chunkCount) · \(Int(speed)) MB/s")
            }
        }

        if isCancelled {
            try? handle.close()
            finish(phase: .idle, message: T("测试已取消", "Benchmark cancelled"))
            return
        }

        // 落盘一次，保证测试的是真实闪存而非页缓存
        _ = fcntl(handle.fileDescriptor, F_FULLFSYNC)
        let writeSeconds = seconds(since: writeStart)
        try? handle.close()

        let finalWrite = Double(written) / 1_048_576 / max(writeSeconds, 0.001)
        publish { state in
            state.writeSpeed = finalWrite
            state.phase = .reading
            state.progress = 0.5
            state.message = T("预热读取缓存…", "Warming up read cache…")
        }

        guard let readHandle = try? FileHandle(forReadingFrom: fileURL) else {
            finish(phase: .failed, message: T("无法读取测试文件", "Unable to read test file"))
            return
        }
        _ = fcntl(readHandle.fileDescriptor, F_NOCACHE, 1)

        var readTotal = 0
        let readStart = DispatchTime.now().uptimeNanoseconds

        while readTotal < written {
            if isCancelled { break }
            guard let data = try? readHandle.read(upToCount: chunkSize), !data.isEmpty else { break }
            readTotal += data.count

            let elapsed = seconds(since: readStart)
            let speed = Double(readTotal) / 1_048_576 / max(elapsed, 0.001)
            publish { state in
                state.readSpeed = speed
                state.progress = 0.5 + Double(readTotal) / Double(max(written, 1)) * 0.5
                state.message = T("读取 \(Int(Double(readTotal) / 1_048_576)) MB · \(Int(speed)) MB/s",
                                  "Reading \(Int(Double(readTotal) / 1_048_576)) MB · \(Int(speed)) MB/s")
            }
        }
        try? readHandle.close()

        if isCancelled {
            finish(phase: .idle, message: T("测试已取消", "Benchmark cancelled"))
            return
        }

        let readSeconds = seconds(since: readStart)
        let finalRead = Double(readTotal) / 1_048_576 / max(readSeconds, 0.001)

        publish { state in
            state.readSpeed = finalRead
            state.writeSpeed = finalWrite
            state.progress = 1
            state.phase = .finished
            state.message = T("测试完成", "Benchmark complete")
            state.isRunning = false
        }
    }

    private func finish(phase: BenchmarkPhase, message: String) {
        publish { state in
            state.phase = phase
            state.message = message
            state.isRunning = false
            state.progress = 0
        }
    }

    private func publish(_ update: @escaping (DiskBenchmark) -> Void) {
        DispatchQueue.main.async { update(self) }
    }

    private func seconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    }
}
