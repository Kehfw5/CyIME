import Foundation

/// 把随 App 打包的 Rime 基础数据（bundle 内 `RimeBase/`）安装到 App Group 的
/// shared 目录，并写入 iOS 首版使用的 `default.custom.yaml`（只启用 pinyin_simp）。
///
/// `RimeBase/` 由 Xcode 构建阶段从 `app/src/main/assets/rime`（rime-wubi 子模块）
/// 复制而来，是一个自包含的简体拼音方案（含 pinyin_simp 词典与 default.yaml）。
enum RimeDataInstaller {
    /// 数据版本：变更数据内容或配置时递增，触发重新安装。
    static let dataVersion = "ios-1"
    private static let markerName = "ios-data-version.txt"

    struct InstallResult {
        let installed: Bool
        let message: String
    }

    static func installIfNeeded() -> InstallResult {
        let fm = FileManager.default
        let dest = AppGroup.rimeSharedURL
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)

        guard let src = Bundle.main.resourceURL?
            .appendingPathComponent("RimeBase", isDirectory: true),
              fm.fileExists(atPath: src.path) else {
            return InstallResult(installed: false, message: "App 内未找到 RimeBase 资源")
        }

        let marker = dest.appendingPathComponent(markerName)
        if let existing = try? String(contentsOf: marker, encoding: .utf8),
           existing.trimmingCharacters(in: .whitespacesAndNewlines) == dataVersion {
            return InstallResult(installed: false, message: "数据已是最新（\(dataVersion)）")
        }

        do {
            try copyContents(from: src, to: dest, fm: fm)
            try writeDefaultCustom(to: dest)
            try dataVersion.write(to: marker, atomically: true, encoding: .utf8)
            return InstallResult(installed: true, message: "已安装 Rime 数据（\(dataVersion)）")
        } catch {
            return InstallResult(installed: false, message: "安装失败：\(error.localizedDescription)")
        }
    }

    private static func copyContents(from src: URL, to dest: URL, fm: FileManager) throws {
        let items = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil)
        for item in items {
            let target = dest.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                try? fm.removeItem(at: target)
            }
            try fm.copyItem(at: item, to: target)
        }
    }

    /// iOS 首版只启用简体全拼（pinyin_simp），避免部署缺失词典的其它方案。
    private static func writeDefaultCustom(to dest: URL) throws {
        let yaml = """
        patch:
          schema_list:
            - schema: pinyin_simp
          menu:
            page_size: 9
        """
        try yaml.write(
            to: dest.appendingPathComponent("default.custom.yaml"),
            atomically: true,
            encoding: .utf8
        )
    }
}
