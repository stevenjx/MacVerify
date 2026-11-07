// Services/BatteryLoadTest.swift
import Foundation
import Combine

enum FindingStatus: String, Codable {
    case passed
    case warning
    case failed
    case info

    var symbol: String {
        switch self {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.octagon.fill"
        case .info: return "info.circle.fill"
        }
    }
}

struct BatteryAuditFinding: Identifiable, Codable {
    var id = UUID()
    let title: String
    let detail: String
    let status: FindingStatus
}

struct BatteryAuditResult: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let score: Int
    let healthPercent: Double?
    let cycleCount: Int
    let voltageDrop: Double?
    let temperatureRise: Double?
    let duration: TimeInterval
    var findings: [BatteryAuditFinding]

    var verdict: String {
        switch score {
        case 85...: return T("电池状态良好", "Battery looks healthy")
        case 70..<85: return T("存在老化迹象", "Signs of wear")
        default: return T("建议更换或人工复核", "Service or manual check advised")
        }
    }
}

final class BatteryLoadTest: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var status: String = T("就绪", "Ready")
    @Published private(set) var samples: Int = 0
    @Published private(set) var voltageSeries: [Double] = []
    @Published private(set) var temperatureSeries: [Double] = []
    @Published private(set) var currentResult: BatteryAuditResult? = nil
    @Published private(set) var elapsed: Double = 0

    private let batteryProvider: () -> BatterySnapshot
    private var targetDuration: TimeInterval = 600

    private var timer: DispatchSourceTimer?
    private let sampleQueue = DispatchQueue(label: "macverify.loadtest.sample", qos: .userInitiated)
    private var stressThreads: [Thread] = []
    private let stopLock = NSLock()
    private var shouldStop = true

    private var startVoltage: Double = 0
    private var lastVoltage: Double = 0
    private var startTemperature: Double?
    private var lastTemperature: Double?
    private var startDate: Date?
    private var startPercent: Double = 0

    init(batteryProvider: @escaping () -> BatterySnapshot = { BatteryStore.readBattery() },
         duration: TimeInterval = 600) {
        self.batteryProvider = batteryProvider
        self.targetDuration = duration
    }

    func start(seconds: Int) {
        guard !isRunning else { return }
        guard batteryProvider().isPresent else {
            status = T("未检测到电池（台式机或无电池设备）", "No battery detected")
            return
        }
        targetDuration = TimeInterval(seconds)

        stopLock.lock()
        shouldStop = false
        stopLock.unlock()

        isRunning = true
        progress = 0
        elapsed = 0
        samples = 0
        voltageSeries = []
        temperatureSeries = []
        currentResult = nil
        startDate = Date()

        let snapshot = batteryProvider()
        startVoltage = snapshot.voltage
        lastVoltage = snapshot.voltage
        startTemperature = snapshot.temperature
        lastTemperature = snapshot.temperature
        startPercent = snapshot.percent

        status = T("正在施加 CPU 负载并采集电池数据…", "Applying CPU load and sampling battery…")
        startStress()

        let timer = DispatchSource.makeTimerSource(queue: sampleQueue)
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler { [weak self] in self?.sample() }
        self.timer = timer
        timer.resume()
    }

    func stop(userInitiated: Bool = true) {
        stopLock.lock()
        let alreadyStopped = shouldStop
        shouldStop = true
        stopLock.unlock()
        guard !alreadyStopped else { return }

        timer?.cancel()
        timer = nil
        stressThreads.forEach { $0.cancel() }
        stressThreads.removeAll()

        DispatchQueue.main.async {
            self.isRunning = false
            self.status = userInitiated ? T("已停止", "Stopped") : T("测试完成", "Complete")
        }
    }

    // MARK: - 负载

    private func startStress() {
        let count = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        for index in 0..<count {
            let thread = Thread { [weak self] in
                var value = Double(index + 1) * 0.7
                while true {
                    // 每轮重新获取，避免线程长期持有 self 导致无法释放
                    guard let engine = self else { return }
                    engine.stopLock.lock()
                    let stop = engine.shouldStop
                    engine.stopLock.unlock()
                    if stop { return }
                    value = (value * 1.000001).truncatingRemainder(dividingBy: 1000) + abs(sin(value)).squareRoot()
                }
            }
            thread.name = "macverify.load.\(index)"
            thread.stackSize = 512 * 1024
            thread.start()
            stressThreads.append(thread)
        }
    }

    // MARK: - 采样

    private func sample() {
        guard let start = startDate else { return }
        let snapshot = batteryProvider()
        let seconds = Date().timeIntervalSince(start)

        DispatchQueue.main.async {
            self.elapsed = seconds
            self.progress = min(1, seconds / max(self.targetDuration, 1))
            self.samples += 1
            if snapshot.voltage > 0 {
                self.lastVoltage = snapshot.voltage
                self.voltageSeries.append(snapshot.voltage)
                if self.voltageSeries.count > 900 { self.voltageSeries.removeFirst() }
            }
            if let temperature = snapshot.temperature {
                self.lastTemperature = temperature
                self.temperatureSeries.append(temperature)
                if self.temperatureSeries.count > 900 { self.temperatureSeries.removeFirst() }
            }
            self.status = T("负载测试进行中 · \(Int(seconds)) 秒 · \(self.samples) 个采样点",
                            "Load test · \(Int(seconds))s · \(self.samples) samples")
        }

        if seconds >= targetDuration {
            finish()
        }
    }

    private func finish() {
        // elapsed 是在主线程异步更新的，这里不能依赖它，否则时长会偏小
        let measuredDuration = startDate.map { Date().timeIntervalSince($0) } ?? elapsed
        stop(userInitiated: false)

        let snapshot = batteryProvider()
        let drop = (startVoltage > 0 && lastVoltage > 0) ? max(0, startVoltage - lastVoltage) : nil
        let rise: Double? = {
            guard let start = startTemperature, let last = lastTemperature else { return nil }
            return last - start
        }()

        var findings: [BatteryAuditFinding] = []
        var weightedScore = 0.0
        var totalWeight = 0.0

        // 容量 / 健康度
        if let health = snapshot.healthPercent {
            let weight = 40.0
            totalWeight += weight
            let score: Double
            switch health {
            case 90...: score = weight
            case 80..<90: score = weight * 0.85
            case 70..<80: score = weight * 0.6
            default: score = weight * 0.25
            }
            weightedScore += score
            findings.append(BatteryAuditFinding(
                title: T("满充容量 \(snapshot.healthCapacity) mAh / 设计容量 \(snapshot.designCapacity) mAh",
                         "Full charge \(snapshot.healthCapacity) mAh / design \(snapshot.designCapacity) mAh"),
                detail: T("健康度 \(String(format: "%.1f", health))%",
                          "Health \(String(format: "%.1f", health))%"),
                status: health >= 80 ? .passed : (health >= 70 ? .warning : .failed)
            ))
        } else {
            findings.append(BatteryAuditFinding(
                title: T("无法读取容量数据", "Capacity data unavailable"),
                detail: T("部分机型不向普通用户态暴露设计容量", "This model does not expose design capacity to user space"),
                status: .info
            ))
        }

        // 循环次数与容量一致性。
        // 注意：Apple 只承诺「1000 次循环后保持 80% 容量」，并没有给出逐循环的衰减曲线，
        // 因此不能按 每循环 0.03% 之类的线性公式去推断"理论容量"再判对错——那是编造出来的判据。
        // 这里只做两件有依据的事：
        //   1) 健康度低于 80% 时按 Apple 的服务建议口径标记；
        //   2) 循环次数极低但容量已明显衰减，提示存在更换电芯/改写数据的可能。
        let weight = 20.0
        totalWeight += weight
        if snapshot.cycleCount > 0 {
            if snapshot.cycleCount < 50, let health = snapshot.healthPercent, health < 90 {
                weightedScore += weight * 0.5
                findings.append(BatteryAuditFinding(
                    title: T("循环次数 \(snapshot.cycleCount) 次，健康度 \(String(format: "%.1f", health))%",
                             "\(snapshot.cycleCount) cycles, health \(String(format: "%.1f", health))%"),
                    detail: T("循环次数很低但容量已明显衰减，建议核对电池序列号与出厂日期，确认是否更换过电芯。",
                              "Very low cycles with noticeable capacity loss — verify the battery serial and manufacture date."),
                    status: .warning
                ))
            } else if let health = snapshot.healthPercent, health < 80 {
                weightedScore += weight * 0.5
                findings.append(BatteryAuditFinding(
                    title: T("循环次数 \(snapshot.cycleCount) / 设计 \(snapshot.designCycleCount) 次",
                             "\(snapshot.cycleCount) of \(snapshot.designCycleCount) design cycles"),
                    detail: T("健康度低于 80%，Apple 对低于该值的电池建议检修。",
                              "Health is below 80%, the threshold Apple uses to recommend service."),
                    status: .warning
                ))
            } else {
                weightedScore += weight
                findings.append(BatteryAuditFinding(
                    title: T("循环次数 \(snapshot.cycleCount) / 设计 \(snapshot.designCycleCount) 次",
                             "\(snapshot.cycleCount) of \(snapshot.designCycleCount) design cycles"),
                    detail: T("Apple 的设计目标是 1000 次循环后仍保持 80% 容量。",
                              "Apple designs for 80% capacity after 1000 cycles."),
                    status: .passed
                ))
            }
        } else {
            totalWeight -= weight
            findings.append(BatteryAuditFinding(
                title: T("循环次数不可用", "Cycle count unavailable"),
                detail: T("该项不参与评分", "Excluded from scoring"),
                status: .info
            ))
        }

        // 负载期间电压变化。
        // 重要口径：这 10 分钟里电量本身在下降，端电压也会随 SOC 下降，
        // 所以该值 ≠ 纯内阻压降。文案必须说明，不能包装成"内阻"。
        let sagWeight = 25.0
        let wasDischarging = !snapshot.isPluggedIn && snapshot.amperage < -0.05
        let validSag = wasDischarging && startPercent < 99 && (drop ?? 0) > 0.005
        if let drop = drop, validSag {
            totalWeight += sagWeight
            if drop <= 0.35 {
                weightedScore += sagWeight
            } else if drop <= 0.9 {
                weightedScore += sagWeight * 0.7
            } else {
                weightedScore += sagWeight * 0.3
            }
            findings.append(BatteryAuditFinding(
                title: T("负载期间电压下降 \(String(format: "%.2f", drop)) V",
                         "Voltage drop under load \(String(format: "%.2f", drop)) V"),
                detail: T("从 \(String(format: "%.2f", startVoltage))V 降至 \(String(format: "%.2f", lastVoltage))V。含电量下降带来的正常压降，数值偏大不必然代表电池异常。",
                          "From \(String(format: "%.2f", startVoltage))V to \(String(format: "%.2f", lastVoltage))V. This includes the normal drop from falling state of charge — a large value is not proof of a fault."),
                status: drop <= 0.35 ? .passed : (drop <= 0.9 ? .warning : .failed)
            ))
        } else {
            findings.append(BatteryAuditFinding(
                title: T("压降未测量", "Voltage drop not measured"),
                detail: !wasDischarging
                    ? T("测试期间接着电源或电流不足以判定放电，无法观察放电压降。拔掉电源后重测可得到该项数据。",
                        "The Mac stayed on AC power or the discharge current was too low. Re-run on battery.")
                    : T("采样期间电压无变化，数据不足。", "No voltage change during sampling."),
                status: .info
            ))
        }

        // 温升
        if let rise = rise, rise > 0 {
            totalWeight += 10
            weightedScore += rise < 12 ? 10 : 4
            findings.append(BatteryAuditFinding(
                title: T("温升 \(String(format: "%.1f", rise)) °C", "Temperature rise \(String(format: "%.1f", rise)) °C"),
                detail: T("负载 10 分钟内的电池温升", "Battery temperature change during the load test"),
                status: rise < 12 ? .passed : .warning
            ))
        } else if snapshot.temperature == nil {
            findings.append(BatteryAuditFinding(
                title: T("温度传感器不可用", "Temperature sensor unavailable"),
                detail: T("该机型未向用户态提供电池温度", "Battery temperature is not exposed on this model"),
                status: .info
            ))
        }

        if snapshot.permanentFailure {
            findings.append(BatteryAuditFinding(
                title: T("电池报告永久性故障", "Battery reports permanent failure"),
                detail: T("建议更换电池后再交易", "Replace the battery before resale"),
                status: .failed
            ))
        }

        let finalScore = totalWeight > 0 ? Int((weightedScore / totalWeight * 100).rounded()) : 0

        let result = BatteryAuditResult(
            date: Date(),
            score: finalScore,
            healthPercent: snapshot.healthPercent,
            cycleCount: snapshot.cycleCount,
            voltageDrop: drop,
            temperatureRise: rise,
            duration: measuredDuration,
            findings: findings
        )

        DispatchQueue.main.async {
            self.currentResult = result
            AuditHistoryStore.shared.append(result)
        }
    }
}

// MARK: - 历史记录

final class AuditHistoryStore: ObservableObject {
    static let shared = AuditHistoryStore()
    private static let key = "macverify.audit.history"

    @Published private(set) var results: [BatteryAuditResult] = []

    private init() {
        load()
    }

    func append(_ result: BatteryAuditResult) {
        results.insert(result, at: 0)
        if results.count > 30 { results.removeLast(results.count - 30) }
        save()
    }

    func clear() {
        results.removeAll()
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key) else { return }
        results = (try? JSONDecoder().decode([BatteryAuditResult].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(results) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
