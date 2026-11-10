// Services/GPUBenchmark.swift
import Foundation
import Metal
import Combine

final class GPUBenchmark: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var framesPerSecond: Double = 0
    @Published private(set) var peakFramesPerSecond: Double = 0
    @Published private(set) var completedBatches: Int = 0
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var message: String = T("就绪", "Ready")
    @Published private(set) var gpuName: String = "—"
    @Published private(set) var supportsMetal: Bool = true

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipeline: MTLComputePipelineState?

    private var workQueue = DispatchQueue(label: "macverify.gpu.stress", qos: .userInitiated)
    private let stateLock = NSLock()
    private var shouldStop = false
    private var completedInWindow = 0
    private var totalCompleted = 0

    private var tickTimer: DispatchSourceTimer?
    private var duration: Double = 30
    private var startedAt: Date?

    init() {
        device = MTLCreateSystemDefaultDevice()
        supportsMetal = device != nil
        gpuName = device?.name ?? "—"
        commandQueue = device?.makeCommandQueue()
        pipeline = Self.makePipeline(device: device)
    }

    private static func makePipeline(device: MTLDevice?) -> MTLComputePipelineState? {
        guard let device = device else { return nil }
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        kernel void macverify_stress(device float *output [[buffer(0)]],
                                    constant uint &rounds [[buffer(1)]],
                                    uint gid [[thread_position_in_grid]]) {
            float x = float(gid) * 0.001f + 1.0f;
            float acc = 0.0f;
            for (uint i = 0; i < rounds; ++i) {
                acc += sin(x) * cos(x) + sqrt(fabs(x));
                x += 0.0001f;
            }
            output[gid] = acc;
        }
        """
        do {
            let library = try device.makeLibrary(source: source, options: nil)
            guard let function = library.makeFunction(name: "macverify_stress") else { return nil }
            return try device.makeComputePipelineState(function: function)
        } catch {
            return nil
        }
    }

    func start(seconds: Int) {
        guard !isRunning, let pipeline = pipeline, let queue = commandQueue, let device = device else {
            message = T("当前设备不支持 Metal 计算管线", "Metal compute pipeline unavailable")
            return
        }

        stateLock.lock()
        shouldStop = false
        completedInWindow = 0
        totalCompleted = 0
        stateLock.unlock()

        duration = Double(seconds)
        startedAt = Date()
        isRunning = true
        progress = 0
        elapsed = 0
        framesPerSecond = 0
        peakFramesPerSecond = 0
        message = T("正在施加持续 GPU 负载…", "Running sustained GPU load…")

        let threadCount = 262_144
        guard let buffer = device.makeBuffer(length: threadCount * MemoryLayout<Float>.size, options: .storageModePrivate) else {
            message = T("无法分配 GPU 缓冲区", "Unable to allocate GPU buffer")
            isRunning = false
            return
        }
        let rounds: UInt32 = 2_048

        workQueue.async { [weak self] in
            while true {
                guard let self = self else { return }
                self.stateLock.lock()
                let stop = self.shouldStop
                self.stateLock.unlock()
                if stop { return }

                guard let commandBuffer = queue.makeCommandBuffer(),
                      let encoder = commandBuffer.makeComputeCommandEncoder() else { break }

                var roundsCopy = rounds
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(buffer, offset: 0, index: 0)
                encoder.setBytes(&roundsCopy, length: MemoryLayout<UInt32>.size, index: 1)
                let threadsPerGroup = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
                encoder.dispatchThreads(MTLSize(width: threadCount, height: 1, depth: 1),
                                        threadsPerThreadgroup: MTLSize(width: threadsPerGroup, height: 1, depth: 1))
                encoder.endEncoding()
                commandBuffer.commit()
                commandBuffer.waitUntilCompleted()

                self.stateLock.lock()
                self.completedInWindow += 1
                self.totalCompleted += 1
                self.stateLock.unlock()
            }
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }
        tickTimer = timer
        timer.resume()
    }

    private func tick() {
        guard let start = startedAt else { return }
        let seconds = Date().timeIntervalSince(start)
        elapsed = seconds
        progress = min(1, seconds / max(duration, 1))

        stateLock.lock()
        let count = completedInWindow
        completedInWindow = 0
        let total = totalCompleted
        stateLock.unlock()

        framesPerSecond = Double(count)
        peakFramesPerSecond = max(peakFramesPerSecond, framesPerSecond)
        completedBatches = total

        if seconds >= duration {
            stop(reason: T("压测完成", "Test complete"))
        }
    }

    func cancel() {
        stop(reason: T("已手动停止", "Stopped by user"))
    }

    private func stop(reason: String) {
        stateLock.lock()
        shouldStop = true
        stateLock.unlock()

        tickTimer?.cancel()
        tickTimer = nil

        DispatchQueue.main.async {
            self.isRunning = false
            self.progress = self.progress >= 1 ? 1 : self.progress
            self.framesPerSecond = 0
            self.message = reason
        }
    }
}
