import Foundation
import OSLog

/// 主 App 与键盘扩展共享的 App Group 容器。
/// 企业证书下需要在 Apple Developer 后台注册 `group.com.cyletix.cyime`，
/// 两个 target 的 entitlements 都引用同一个 group。
enum AppGroup {
    static let identifier = "group.com.cyletix.cyime"

    private static let logger = Logger(subsystem: "com.cyletix.cyime", category: "app-group")
    private static let logQueue = DispatchQueue(label: "com.cyletix.cyime.log")

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    /// App Group 不可用时回退到当前进程自己的目录，至少保证单进程能跑。
    static var rootURL: URL {
        if let containerURL {
            return containerURL
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent("CyIME", isDirectory: true)
    }

    static var rimeURL: URL { rootURL.appendingPathComponent("rime", isDirectory: true) }
    static var modelsURL: URL { rootURL.appendingPathComponent("models", isDirectory: true) }
    static var logsURL: URL { rootURL.appendingPathComponent("logs", isDirectory: true) }
    static var ipcURL: URL { rootURL.appendingPathComponent("ipc", isDirectory: true) }

    static func prepare() {
        for url in [rootURL, rimeURL, modelsURL, logsURL, ipcURL] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        if containerURL == nil {
            logger.error("App Group \(identifier, privacy: .public) 不可用，使用本地回退目录")
        }
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
