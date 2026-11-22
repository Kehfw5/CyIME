import Foundation
import OSLog

/// 主 App 与键盘扩展共享的 App Group 容器。
///
/// 当前签名使用的是第三方共享企业证书（Team `2RM563997N`），它只授权了
/// 5 个固定的 App Group（`group.0541a8a73a5a6c62.1 … .5`），
/// 因此这里按优先级探测：先试自建 group（将来换自有账号时生效），
/// 再依次试证书已授权的 group，取第一个真正可用的。
///
/// 注意：这些 group 是共享证书的所有使用者共用的，容器里可能有别人的数据。
/// 所以统一把本项目文件放在 `CyIME/` 子目录下，避免撞名。
enum AppGroup {
    /// 自建群组：只在拥有可登录开发者后台的账号时才会生效。
    static let preferredIdentifier = "group.com.cyletix.cyime"

    /// 当前共享企业证书 profile 中已授权的 App Group。
    static let provisionedIdentifiers = [
        "group.0541a8a73a5a6c62.1",
        "group.0541a8a73a5a6c62.2",
        "group.0541a8a73a5a6c62.3",
        "group.0541a8a73a5a6c62.4",
        "group.0541a8a73a5a6c62.5",
    ]

    /// 探测顺序：自建优先，其次证书授权。
    static let candidates = [preferredIdentifier] + provisionedIdentifiers

    /// 共享容器根下的项目子目录，避免和其他 App 撞文件。
    private static let namespace = "CyIME"

    private static let logger = Logger(subsystem: "com.cyletix.cyime", category: "app-group")
    private static let logQueue = DispatchQueue(label: "com.cyletix.cyime.log")

    private static func container(for identifier: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// 第一个真正可用的 group ID；全部探测失败则为 nil。
    static let resolvedIdentifier: String? = candidates.first { container(for: $0) != nil }

    /// 各候选 group 的可用性，供诊断页展示。
    static var probeResults: [(String, Bool)] {
        candidates.map { ($0, container(for: $0) != nil) }
    }

    static var containerURL: URL? {
        guard let resolvedIdentifier else { return nil }
        return container(for: resolvedIdentifier)
    }

    static var defaults: UserDefaults? {
        guard let resolvedIdentifier else { return nil }
        return UserDefaults(suiteName: resolvedIdentifier)
    }

    /// App Group 不可用时回退到当前进程自己的目录，至少保证单进程能跑。
    static var rootURL: URL {
        if let containerURL {
            return containerURL.appendingPathComponent(namespace, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("CyIME", isDirectory: true)
    }

    static var rimeURL: URL { rootURL.appendingPathComponent("rime", isDirectory: true) }
    /// librime 的 shared_data_dir：放 schema/词库。
    static var rimeSharedURL: URL { rimeURL.appendingPathComponent("shared", isDirectory: true) }
    /// librime 的 user_data_dir：放用户词典与 build 产物（.bin）。
    static var rimeUserURL: URL { rimeURL.appendingPathComponent("user", isDirectory: true) }
    static var modelsURL: URL { rootURL.appendingPathComponent("models", isDirectory: true) }
    static var logsURL: URL { rootURL.appendingPathComponent("logs", isDirectory: true) }
    static var ipcURL: URL { rootURL.appendingPathComponent("ipc", isDirectory: true) }

    static func prepare() {
        for url in [rootURL, rimeURL, rimeSharedURL, rimeUserURL, modelsURL, logsURL, ipcURL] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        if let resolvedIdentifier {
            logger.info("App Group 可用: \(resolvedIdentifier, privacy: .public)")
        } else {
            logger.error("所有 App Group 均不可用，使用本地回退目录")
        }
        let resolved = resolvedIdentifier ?? "nil"
        appendLog("AppGroup resolved=\(resolved) root=\(rootURL.path)")
    }

    static func appendLog(_ message: String, file: String = #fileID, line: Int = #line) {
        let formatter = ISO8601DateFormatter()
        let text = "\(formatter.string(from: Date())) [\(file):\(line)] \(message)\n"
        logQueue.sync {
            let url = logsURL.appendingPathComponent("diagnostics.log")
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(text.utf8))
            } else {
                try? Data(text.utf8).write(to: url, options: .atomic)
            }
        }
    }

    static func tailLog(maxLines: Int = 100) -> String {
        let url = logsURL.appendingPathComponent("diagnostics.log")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "暂无日志"
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(maxLines).joined(separator: "\n")
    }
}
