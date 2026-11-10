// Services/BiometricTemplates.swift
//
// 读取「当前用户已录入几枚指纹模板」。
//
// 为什么需要它：录入本身只能由系统完成，第三方 App 拿不到录入接口，
// 但可以用 /usr/bin/bioutil -c 这个只读命令看到模板数量。
// 于是录入这件事变成可验证的：开始前记下数量，用户在系统面板录完一枚，
// 数量 +1 —— 这就是「真的录进去了」的证据，而不是 App 自己假装走完流程。
import Foundation

enum BiometricTemplates {

    /// 已录入的模板数；读不到返回 nil（不猜、不退化成 0）。
    static func count() -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/bioutil")
        process.arguments = ["-c"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// bioutil 的输出形如：
    ///     User 501:	1 biometric template(s)
    ///     Operation performed successfully.
    /// 取「biometric template(s)」前面那一段里最后的数字（第一段是 uid）。
    nonisolated static func parse(_ output: String) -> Int? {
        guard let marker = output.range(of: "biometric template"),
              let colon = output[output.startIndex..<marker.lowerBound].lastIndex(of: ":")
        else { return nil }

        // 冒号与「biometric template」之间必须正好是一个数字；
        // 少了数字就返回 nil，绝不把前面的 uid 当数量。
        let tail = output[output.index(after: colon)..<marker.lowerBound]
        let numbers = tail.split(whereSeparator: { !$0.isNumber })
        guard numbers.count == 1, let value = Int(numbers[0]) else { return nil }
        return value
    }
}
