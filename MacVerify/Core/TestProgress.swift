// Core/TestProgress.swift
//
// 交互测试的完成状态。只记内存，不落盘：
// 换一台机器、或重启 App 之后应该回到「未测试」，
// 否则上一台机器的勾会跟着走，验机时就成了假信息。
import Foundation
import Combine

final class TestProgress: ObservableObject {
    static let shared = TestProgress()

    @Published private(set) var completed: Set<String> = []

    private init() {}

    func markCompleted(_ key: String) {
        guard !completed.contains(key) else { return }
        completed.insert(key)
    }

    func isCompleted(_ key: String) -> Bool {
        completed.contains(key)
    }
}
