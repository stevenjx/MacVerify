// Services/BatteryService.swift
import Foundation
import IOKit
import Combine

final class BatteryStore: ObservableObject {
    @Published private(set) var battery = BatterySnapshot()
    @Published private(set) var resistanceMilliohms: Double? = nil
    @Published private(set) var resistanceSamples: Int = 0

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "macverify.battery.sample", qos: .utility)

    private struct ElectricalSample {
        let voltage: Double
        let amperage: Double
    }
    private var recentSamples: [ElectricalSample] = []
    private var resistanceEstimates: [Double] = []

    init() {
        read()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in self?.read() }
        self.timer = timer
        timer.resume()
    }

    deinit {
        timer?.cancel()
    }

    func refresh() {
        queue.async { [weak self] in self?.read() }
    }

    // MARK: - 读取

    private func read() {
        let snapshot = Self.readBattery()
        let resistance = updateResistance(with: snapshot)

        DispatchQueue.main.async {
            self.battery = snapshot
            self.resistanceMilliohms = resistance
            self.resistanceSamples = self.resistanceEstimates.count
        }
    }

    static func readBattery() -> BatterySnapshot {
        var snapshot = BatterySnapshot()
        let service = IOKit.firstService(matching: "AppleSmartBattery")
        guard service != 0 else { return snapshot }
        defer { IOObjectRelease(service) }

        let properties = IOKit.properties(service)
        guard !properties.isEmpty else { return snapshot }

        snapshot.isPresent = true
        snapshot.batteryInstalled = properties["BatteryInstalled"] as? Bool ?? true

        let batteryData = properties["BatteryData"] as? [String: Any] ?? [:]

        snapshot.designCapacity = intValue(properties["DesignCapacity"]) ?? intValue(batteryData["DesignCapacity"]) ?? 0
        snapshot.nominalCapacity = intValue(batteryData["NominalChargeCapacity"])
            ?? intValue(batteryData["FullChargeCapacity"])
            ?? intValue(properties["AppleRawMaxCapacity"])
            ?? 0
        snapshot.rawMaxCapacity = intValue(properties["AppleRawMaxCapacity"])
            ?? intValue(batteryData["FullChargeCapacity"])
            ?? 0
        snapshot.remainingCapacity = intValue(properties["AppleRawCurrentCapacity"])
            ?? intValue(batteryData["RemainingCapacity"])
            ?? 0

        let rawPercent = intValue(properties["CurrentCapacity"]) ?? intValue(batteryData["CurrentCapacity"]) ?? 0
        let maxPercent = intValue(properties["MaxCapacity"]) ?? 100
        if maxPercent <= 100 {
            snapshot.percent = Double(rawPercent)
        } else if snapshot.rawMaxCapacity > 0 {
            snapshot.percent = Double(snapshot.remainingCapacity) / Double(snapshot.rawMaxCapacity) * 100
        }

        snapshot.cycleCount = intValue(properties["CycleCount"]) ?? intValue(batteryData["CycleCount"]) ?? 0
        snapshot.designCycleCount = intValue(properties["DesignCycleCount9C"]) ?? 1000

        if let voltage = intValue(properties["Voltage"]), voltage > 0 {
            snapshot.voltage = Double(voltage) / 1000
        }
        // 电池组额定电压：部分机型（多为 Intel）在 IORegistry 中直接给出，
        // Apple Silicon 上通常没有该键。取不到就留 nil，不用假设值代替。
        if let designMillivolts = intValue(properties["DesignVoltage"]) ?? intValue(batteryData["DesignVoltage"]),
           designMillivolts > 4000, designMillivolts < 20000 {
            snapshot.designVoltage = Double(designMillivolts) / 1000
        }
        if let rawAmperage = intValue(properties["InstantAmperage"]) ?? intValue(properties["Amperage"]) {
            snapshot.amperage = Double(rawAmperage) / 1000
        }

        if let rawTemperature = intValue(properties["Temperature"]), rawTemperature > 0 {
            let celsius = Double(rawTemperature) / 100
            if celsius > -20, celsius < 120 { snapshot.temperature = celsius }
        }

        snapshot.isCharging = properties["IsCharging"] as? Bool ?? false
        snapshot.isPluggedIn = properties["ExternalConnected"] as? Bool ?? false
        snapshot.isFullyCharged = properties["FullyCharged"] as? Bool ?? false
        snapshot.permanentFailure = (intValue(properties["PermanentFailureStatus"]) ?? 0) != 0

        snapshot.serialNumber = (properties["Serial"] as? String) ?? (properties["BatterySerialNumber"] as? String) ?? "—"
        snapshot.manufacturer = (properties["Manufacturer"] as? String) ?? "—"
        snapshot.gaugeModel = (properties["DeviceName"] as? String) ?? ""

        if let remaining = intValue(properties["TimeRemaining"]), remaining > 0, remaining < 65_535 {
            snapshot.timeToEmpty = remaining
        }
        if let avgEmpty = intValue(properties["AvgTimeToEmpty"]), avgEmpty > 0, avgEmpty < 65_535, snapshot.timeToEmpty == nil {
            snapshot.timeToEmpty = avgEmpty
        }
        if let avgFull = intValue(properties["AvgTimeToFull"]), avgFull > 0, avgFull < 65_535 {
            snapshot.timeToFull = avgFull
        }

        if let adapter = properties["AdapterDetails"] as? [String: Any] {
            snapshot.adapterWatts = intValue(adapter["Watts"])
            snapshot.adapterName = adapter["Name"] as? String
            snapshot.adapterManufacturer = adapter["Manufacturer"] as? String
        }

        return snapshot
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let int64 = value as? Int64 { return Int(int64) }
        return nil
    }

    // MARK: - 内阻估算（ΔV/ΔI，仅在电流明显变化时采样）

    private func updateResistance(with snapshot: BatterySnapshot) -> Double? {
        guard snapshot.isPresent, snapshot.voltage > 0 else { return resistanceEstimates.last }

        recentSamples.append(ElectricalSample(voltage: snapshot.voltage, amperage: snapshot.amperage))
        if recentSamples.count > 12 { recentSamples.removeFirst() }

        guard let current = recentSamples.last else { return resistanceEstimates.last }

        // 找一组电流差足够大的样本
        for sample in recentSamples.dropLast() {
            let deltaCurrent = abs(current.amperage - sample.amperage)
            guard deltaCurrent >= 0.15 else { continue }
            let deltaVoltage = abs(current.voltage - sample.voltage)
            let resistance = deltaVoltage / deltaCurrent * 1000
            if resistance > 0, resistance < 500 {
                resistanceEstimates.append(resistance)
                if resistanceEstimates.count > 40 { resistanceEstimates.removeFirst() }
            }
            break
        }

        guard !resistanceEstimates.isEmpty else { return nil }
        let sorted = resistanceEstimates.sorted()
        return sorted[sorted.count / 2]
    }

    // MARK: - 派生状态

    var healthPercent: Double? { battery.healthPercent }

    var healthCategory: (text: String, level: Int) {
        (battery.healthGrade.title, battery.healthGrade.level)
    }
}
