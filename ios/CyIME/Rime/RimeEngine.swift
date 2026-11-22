import Foundation

/// 一次输入操作后的完整状态快照。
struct RimeState {
    /// 待上屏文本；nil 表示没有。
    let commit: String?
    /// 当前编码串（preedit）。
    let preedit: String
    /// 当前候选页。
    let candidates: [String]
}

/// Swift 侧对 librime 的封装。RimeBridge 是 Obj-C++ 桥，这里再包一层纯 Swift API，
/// 让 KeyboardModel 不必接触 C 结构体 / 函数指针。
@MainActor
final class RimeEngine {
    static let shared = RimeEngine()

    private let bridge = RimeBridge.shared()

    /// librime 是否真正可用（初始化成功且加载到 schema）。
    /// 未就绪时键盘回退到 stub，避免“打不出字”的假象。
    private(set) var ready = false

    /// 是否已完成 librime 初始化（避免重复 initialize）。
    private var didSetup = false

    /// 首次 setup 时记录的数据目录，供未就绪时自动重试。
    private var dataDirs: (shared: String, user: String)?

    /// 上次重试时间，避免每次按键都重建会话。
    private var lastRetryAt: Date = .distantPast

    var isReady: Bool { ready }

    /// 设置数据目录并初始化引擎 + 创建会话。
    /// - Parameters:
    ///   - sharedDataDir: schema/词库目录（共享）。
    ///   - userDataDir: 用户词典与 build 产物目录。
    func setup(sharedDataDir: String, userDataDir: String) -> Bool {
        dataDirs = (sharedDataDir, userDataDir)
        if didSetup {
            refreshReady()
            return ready
        }
        let start = CFAbsoluteTimeGetCurrent()
        guard bridge.setup(withSharedDataDir: sharedDataDir, userDataDir: userDataDir) else {
            ready = false
            return false
        }
        didSetup = true
        guard bridge.createSession() else {
            ready = false
            return false
        }
        refreshReady()
        if ready {
            warmUp()
        }
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        AppGroup.appendLog("Rime setup \(ms)ms ready=\(ready)")
        return ready
    }

    /// 数据部署可能在键盘启动之后才完成：未就绪时重建会话再试一次，
    /// 让键盘自动恢复，而不必让用户手动切换键盘。
    func ensureReady() -> Bool {
        if ready { return true }
        guard let dataDirs else { return false }
        guard Date().timeIntervalSince(lastRetryAt) > 2 else { return false }
        lastRetryAt = Date()
        if didSetup {
            bridge.destroySession()
            guard bridge.createSession() else { return false }
            refreshReady()
            if ready {
                warmUp()
                AppGroup.appendLog("Rime recovered after retry")
            }
        } else {
            return setup(sharedDataDir: dataDirs.shared, userDataDir: dataDirs.user)
        }
        return ready
    }

    /// 触发一次翻译，让词典/表在用户按键前完成首次加载。
    private func warmUp() {
        let start = CFAbsoluteTimeGetCurrent()
        _ = process(keycode: 0x61)   // 'a'：只组码，不上屏
        _ = clear()
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        AppGroup.appendLog("Rime warmup \(ms)ms")
    }

    /// 完整部署（构建 .bin）。首次运行较慢，由主 App 调用。
    /// 部署后重建会话并刷新 schema 状态。
    func deploy() -> Bool {
        guard didSetup else { return false }
        let ok = bridge.deploy()
        bridge.destroySession()
        _ = bridge.createSession()
        refreshReady()
        if ready { warmUp() }
        return ok && ready
    }

    /// 无 schema（数据未部署）时视为未就绪，键盘回退 stub。
    private func refreshReady() {
        let schema = bridge.schemaId() ?? ""
        ready = !schema.isEmpty
    }

    /// 用临时会话预览一串编码（滑行输入），不影响当前组字状态。
    func previewCandidates(code: String) -> [String] {
        guard ready, !code.isEmpty else { return [] }
        return bridge.previewCandidates(forCode: code)
    }

    @discardableResult
    func process(keycode: Int32, mask: Int32 = 0) -> RimeState {
        bridge.processKey(keycode, mask: mask)
        return readState()
    }

    @discardableResult
    func selectCandidate(_ index: Int) -> RimeState {
        bridge.selectCandidate(at: index)
        return readState()
    }

    @discardableResult
    func commit() -> RimeState {
        bridge.commitComposition()
        return readState()
    }

    @discardableResult
    func clear() -> RimeState {
        bridge.clearComposition()
        return readState()
    }

    func readState() -> RimeState {
        RimeState(
            commit: bridge.takeCommit(),
            preedit: bridge.preedit() ?? "",
            candidates: bridge.candidates()
        )
    }
}
