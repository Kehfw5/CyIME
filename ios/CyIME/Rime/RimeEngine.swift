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

    private let bridge = RimeBridge.shared

    /// librime 是否真正可用（初始化成功且加载到 schema）。
    /// 未就绪时键盘回退到 stub，避免“打不出字”的假象。
    private(set) var ready = false

    var isReady: Bool { ready }

    /// 设置数据目录并初始化引擎 + 创建会话。
    /// - Parameters:
    ///   - sharedDataDir: schema/词库目录（共享）。
    ///   - userDataDir: 用户词典与 build 产物目录。
    func setup(sharedDataDir: String, userDataDir: String) -> Bool {
        guard bridge.setup(withSharedDataDir: sharedDataDir, userDataDir: userDataDir) else {
            ready = false
            return false
        }
        guard bridge.createSession() else {
            ready = false
            return false
        }
        // 没有 schema（数据未部署）时视为未就绪，回退 stub。
        let schema = bridge.schemaId() ?? ""
        ready = !schema.isEmpty
        return ready
    }

    /// 完整部署（构建 .bin）。首次运行较慢，由主 App 调用。
    func deploy() -> Bool {
        bridge.deploy()
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
