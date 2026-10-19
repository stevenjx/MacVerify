// Services/CPUBenchmark.swift
import Foundation
import Combine

final class CPUBenchmark: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var singleCoreMops: Double = 0
    @Published private(set) var multiCoreMops: Double = 0
    @Published private(set) var message: String = T("就绪", "Ready")
    @Published private(set) var progress: Double = 0

    private let queue = DispatchQueue(label: "maccheck.cpu.benchmark", qos: .userInitiated)

    /// 防止编译器把纯计算循环优化掉
    private static var sink: Double = 0

    func start() {
        guard !isRunning else { return }
        isRunning = true
        progress = 0
        singleCoreMops = 0
        multiCoreMops = 0
        message = T("正在测试单核性能…", "Measuring single-core throughput…")

        queue.async { [weak self] in
            guard let self = self else { return }

            let iterations = 8_000_000
            let single = Self.workload(iterations: iterations, threads: 1)
            DispatchQueue.main.async {
                self.singleCoreMops = Double(iterations) / single / 1_000_000
                self.progress = 0.5
                self.message = T("正在测试多核性能…", "Measuring multi-core throughput…")
            }

            let threads = max(1, ProcessInfo.processInfo.activeProcessorCount)
            let multi = Self.workload(iterations: iterations, threads: threads)
            let totalOps = Double(iterations * threads)

            DispatchQueue.main.async {
                self.multiCoreMops = totalOps / multi / 1_000_000
                self.progress = 1
                self.isRunning = false
                self.message = T("测试完成", "Complete")
            }
        }
    }

    private static func workload(iterations: Int, threads: Int) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        let group = DispatchGroup()

        for threadIndex in 0..<threads {
            group.enter()
            Thread.detachNewThread {
                var value = Double(threadIndex + 1) * 0.31
                for index in 0..<iterations {
                    value += (abs(sin(value) * cos(value)) + Double(index % 97)).squareRoot()
                    if value > 1_000_000 { value = value.truncatingRemainder(dividingBy: 1000) }
                }
                sink = value
                group.leave()
            }
        }

        group.wait()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000_000
    }
}
