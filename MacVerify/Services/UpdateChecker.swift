// Services/UpdateChecker.swift
//
// 版本检查：只向 GitHub 的公开接口问一句「最新 release 是哪个版本」，
// 有新版本时在侧栏版本号处提示，点一下把官方 DMG 下到「下载」文件夹。
//
// 边界刻意守住三条：
// 1. 只发一次 GET，不附带任何机器信息；检测过程本身仍然全程离线。
// 2. 失败就安静地保持原样——验机工具不该因为网络断了就弹一堆红字。
// 3. 不自动安装、不自动打开安装器，只把文件放进「下载」并在访达里选中。
import Foundation
import AppKit

/// 一个可下载的 release。
struct AppRelease: Equatable {
    let version: String        // 1.0.12
    let tag: String            // v1.0.12
    let assetName: String      // MacVerify-1.0.12.dmg
    let downloadURL: URL
}

enum UpdateStatus: Equatable {
    case idle
    case checking
    case upToDate(String)
    case available(AppRelease)
    case downloading(progress: Double, release: AppRelease)
    case downloaded(URL)
    case failed(String)
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    static let owner = "stevenjx"
    static let repo = "MacVerify"
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!

    /// 两次自动检查之间至少隔 6 小时。GitHub 对未认证请求有速率限制，
    /// 每次启动都问一遍既没必要也不礼貌。
    private static let interval: TimeInterval = 6 * 60 * 60
    private static let lastCheckKey = "macverify.update.lastCheck"

    @Published private(set) var status: UpdateStatus = .idle

    var currentVersion: String { BuildInfo.version }

    // MARK: - 检查

    /// 启动时调用：距上次检查不足 6 小时就什么都不做。
    func checkIfNeeded() async {
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        if let last = last, Date().timeIntervalSince(last) < Self.interval { return }
        await check()
    }

    func check() async {
        guard !isBusy else { return }
        status = .checking
        do {
            var request = URLRequest(url: Self.latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200:
                break
            case 401, 403, 404:
                // 私有仓库与「还没有 release」在匿名请求下都是 404，分不开也不必分：
                // 两种情况都不是用户在这台机器上能修的
                throw UpdateError.message(T("仓库未公开或还没有 release（HTTP \(code)）",
                                            "the repository is private or has no release (HTTP \(code))"))
            default:
                throw UpdateError.message(T("服务器返回 \(code)", "the server returned \(code)"))
            }
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

            guard let release = Self.parseLatestRelease(data) else {
                throw UpdateError.message(T("最新的 release 里没有可下载的 DMG",
                                            "the latest release has no downloadable DMG"))
            }
            if Self.isNewer(release.version, than: currentVersion) {
                status = .available(release)
            } else {
                status = .upToDate(release.version)
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: - 点击版本号

    /// 有新版本 → 下载；已下载 → 在访达里选中；其余 → 重新查一次。
    func handleVersionTap() async {
        switch status {
        case .available(let release):
            await download(release)
        case .downloaded(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .downloading, .checking:
            return
        case .idle, .upToDate, .failed:
            await check()
        }
    }

    private var isBusy: Bool {
        if case .downloading = status { return true }
        if case .checking = status { return true }
        return false
    }

    // MARK: - 下载

    private func download(_ release: AppRelease) async {
        status = .downloading(progress: 0, release: release)
        let downloader = FileDownloader { [weak self] fraction in
            Task { @MainActor in
                guard let self = self else { return }
                // 只在百分比真的变化时才刷新，避免每块数据都重绘侧栏
                if case .downloading(let current, _) = self.status,
                   Int(fraction * 100) == Int(current * 100) { return }
                self.status = .downloading(progress: fraction, release: release)
            }
        }
        do {
            let temp = try await downloader.start(release.downloadURL)
            let destination = try Self.destination(for: release.assetName)
            try FileManager.default.moveItem(at: temp, to: destination)
            status = .downloaded(destination)
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            if let temp = downloader.tempFile { try? FileManager.default.removeItem(at: temp) }
            status = .failed(error.localizedDescription)
        }
    }

    /// 存到「下载」；重名时加序号，绝不覆盖用户已有的文件。
    nonisolated static func destination(for assetName: String) throws -> URL {
        guard let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            throw UpdateError.message(T("找不到「下载」文件夹", "the Downloads folder could not be located"))
        }
        var url = folder.appendingPathComponent(assetName)
        var index = 2
        let base = (assetName as NSString).deletingPathExtension
        let ext = (assetName as NSString).pathExtension
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base)-\(index).\(ext)")
            index += 1
        }
        return url
    }

    // MARK: - 解析（纯函数，便于测试）

    nonisolated static func parseLatestRelease(_ data: Data) -> AppRelease? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = root["tag_name"] as? String, !tag.isEmpty else { return nil }

        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        let assets = root["assets"] as? [[String: Any]] ?? []

        let dmgs: [(String, URL)] = assets.compactMap { asset in
            guard let name = asset["name"] as? String,
                  name.lowercased().hasSuffix(".dmg"),
                  let raw = asset["browser_download_url"] as? String,
                  let url = URL(string: raw)
            else { return nil }
            return (name, url)
        }

        // 优先名字里带版本号的那个；只有一堆 DMG 时退回第一个
        guard let picked = dmgs.first(where: { $0.0.contains(version) }) ?? dmgs.first else { return nil }
        return AppRelease(version: version, tag: tag, assetName: picked.0, downloadURL: picked.1)
    }

    /// 远端版本是否高于本机。逐段比较数字，缺的段按 0 算（1.0 与 1.0.0 相等）。
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = numbers(in: candidate), let b = numbers(in: current) else { return false }
        for index in 0..<max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    /// "v1.0.12" → [1, 0, 12]；带后缀的 "1.1.0-beta" 只取数字段。
    nonisolated static func numbers(in raw: String) -> [Int]? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        if let dash = text.firstIndex(of: "-") { text = String(text[text.startIndex..<dash]) }
        let parts = text.split(separator: ".")
        guard !parts.isEmpty else { return nil }
        var result: [Int] = []
        for part in parts {
            guard let value = Int(part) else { return nil }
            result.append(value)
        }
        return result
    }
}

enum UpdateError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

/// URLSession 的下载委托：上报进度、把临时文件搬到不会被回收的位置。
private final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private(set) var tempFile: URL?

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func start(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation = continuation else { return }
        self.continuation = nil
        if case .failure = result { tempFile = nil }
        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // 这个回调一返回，location 就会被系统删掉，必须先搬走
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacVerify-download-\(UUID().uuidString).dmg")
        do {
            try FileManager.default.moveItem(at: location, to: temp)
            tempFile = temp
            finish(.success(temp))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error { finish(.failure(error)) }
    }
}
