import Combine
import CoreGraphics
import Foundation

enum InputMode: String, Equatable {
    case chinese = "中"
    case english = "英"
    case numbers = "123"
}

/// Shift 三态：普通 / 单次大写 / 大写锁定（双击 Shift）。
enum ShiftState: Equatable {
    case off
    case on
    case caps
}

enum KeyAction: Hashable {
    case character(String)
    case shift
    case delete
    case space
    case ret
    case globe
    case toggleMode
    case toggleNumbers
    case dismiss
}

struct KeySpec: Identifiable, Hashable {
    let id: String
    let label: String
    let action: KeyAction
    var width: CGFloat = 1
    var isSpecial: Bool = false
    var isAccent: Bool = false
    var isSpacer: Bool = false
    /// 右上角小提示（26 键上滑数字）。
    var hint: String?
    /// 上滑动作。
    var swipeUp: KeyAction?
    /// 是否空格键（支持滑动移动光标）。
    var isSpace: Bool = false
}

/// X11 keysym 常量，供 librime 的 process_key 使用。
enum RimeKeycode {
    static let space: Int32 = 0x0020
    static let backspace: Int32 = 0xFF08
    static let ret: Int32 = 0xFF0D
    static let pageUp: Int32 = 0xFF55
    static let pageDown: Int32 = 0xFF56
}

/// librime 未就绪时的占位中文引擎。
struct StubChineseEngine {
    private let table: [String: [String]] = [
        "ni": ["你", "呢", "尼", "泥", "逆"],
        "hao": ["好", "号", "浩", "豪", "耗"],
        "wo": ["我", "握", "窝", "卧"],
        "shi": ["是", "时", "事", "十", "使"],
        "zhong": ["中", "种", "重", "众", "钟"],
        "nihao": ["你好"],
        "shijie": ["世界"],
        "zhongguo": ["中国"],
        "cyime": ["CyIME"]
    ]

    func candidates(for composing: String) -> [String] {
        guard !composing.isEmpty else { return [] }
        let key = composing.lowercased()
        if let exact = table[key] { return exact }

        var seen = Set<String>()
        var result: [String] = []
        for (_, words) in table
            .filter({ $0.key.hasPrefix(key) })
            .sorted(by: { $0.key.count < $1.key.count }) {
            for word in words where seen.insert(word).inserted {
                result.append(word)
            }
        }
        return result.isEmpty ? [composing] : Array(result.prefix(12))
    }
}

@MainActor
final class KeyboardModel: ObservableObject {
    @Published private(set) var mode: InputMode = .chinese
    @Published private(set) var shiftState: ShiftState = .off
    @Published private(set) var composing = ""
    @Published private(set) var candidates: [String] = []
    @Published private(set) var status = "Rime 未就绪"
    @Published private(set) var hasText = false

    private let insertText: (String) -> Void
    private let deleteBackward: () -> Void
    private let advanceInputMode: () -> Void
    private let dismissKeyboard: () -> Void
    private let moveCursor: (Int) -> Void

    private let stub = StubChineseEngine()
    private let rime = RimeEngine.shared
    private var lastShiftTap: Date = .distantPast

    private var usesRime: Bool { rime.isReady }

    init(
        insertText: @escaping (String) -> Void,
        deleteBackward: @escaping () -> Void,
        advanceInputMode: @escaping () -> Void,
        dismissKeyboard: @escaping () -> Void,
        moveCursor: @escaping (Int) -> Void
    ) {
        self.insertText = insertText
        self.deleteBackward = deleteBackward
        self.advanceInputMode = advanceInputMode
        self.dismissKeyboard = dismissKeyboard
        self.moveCursor = moveCursor
        refreshStatus()
    }

    var modeLabel: String { mode.rawValue }
    var isShifted: Bool { shiftState != .off }
    var isCapsLock: Bool { shiftState == .caps }

    var rows: [[KeySpec]] {
        switch mode {
        case .numbers: return numberRows
        case .chinese, .english: return letterRows
        }
    }

    // MARK: - 按键

    func tap(_ action: KeyAction) {
        switch action {
        case .character(let value):
            switch mode {
            case .chinese:
                if usesRime || rime.ensureReady() {
                    apply(rime.process(keycode: keycode(for: value)))
                } else {
                    composing += value.lowercased()
                    refreshCandidates()
                }
            case .english:
                insertText(display(value))
                if shiftState == .on { shiftState = .off }
            case .numbers:
                insertText(value)
            }
        case .shift:
            handleShiftTap()
        case .delete:
            if usesRime && !composing.isEmpty {
                apply(rime.process(keycode: RimeKeycode.backspace))
            } else if !composing.isEmpty {
                composing.removeLast()
                refreshCandidates()
            } else {
                deleteBackward()
            }
        case .space:
            if usesRime {
                if composing.isEmpty { insertText(" ") } else { apply(rime.process(keycode: RimeKeycode.space)) }
            } else if !composing.isEmpty, let first = candidates.first {
                commitCandidate(first)
            } else {
                insertText(" ")
            }
        case .ret:
            if usesRime {
                if composing.isEmpty { insertText("\n") } else { apply(rime.commit()) }
            } else if composing.isEmpty {
                insertText("\n")
            } else {
                commitCandidate(composing)
            }
        case .globe:
            advanceInputMode()
        case .toggleMode:
            mode = (mode == .english) ? .chinese : .english
            resetShift()
            clearComposing()
            refreshStatus()
        case .toggleNumbers:
            mode = (mode == .numbers) ? .chinese : .numbers
            resetShift()
            clearComposing()
            refreshStatus()
        case .dismiss:
            dismissKeyboard()
        }
    }

    /// 空格横向滑动移动光标。
    func moveCursorBy(_ steps: Int) {
        guard steps != 0 else { return }
        moveCursor(steps)
    }

    func selectCandidate(at index: Int) {
        guard index >= 0, index < candidates.count else { return }
        if usesRime {
            apply(rime.selectCandidate(index))
        } else {
            commitCandidate(candidates[index])
        }
    }

    func pageUp() {
        guard usesRime else { return }
        apply(rime.process(keycode: RimeKeycode.pageUp))
    }

    func pageDown() {
        guard usesRime else { return }
        apply(rime.process(keycode: RimeKeycode.pageDown))
    }

    func commitCandidate(_ text: String) {
        guard !text.isEmpty else { return }
        insertText(text)
        clearComposing()
        status = "已上屏：\(text)"
    }

    func updateContext(hasText: Bool) {
        self.hasText = hasText
    }

    func refreshEngineStatus() {
        refreshStatus()
    }

    // MARK: - 内部

    private func handleShiftTap() {
        let now = Date()
        switch shiftState {
        case .off:
            shiftState = .on
        case .on:
            // 双击 Shift 进入大写锁定。
            shiftState = (now.timeIntervalSince(lastShiftTap) < 0.35) ? .caps : .off
        case .caps:
            shiftState = .off
        }
        lastShiftTap = now
    }

    private func resetShift() {
        if shiftState != .caps { shiftState = .off }
    }

    private func apply(_ state: RimeState) {
        if let commit = state.commit, !commit.isEmpty {
            insertText(commit)
        }
        composing = state.preedit
        candidates = state.candidates
        refreshStatus()
    }

    private func keycode(for character: String) -> Int32 {
        Int32(character.lowercased().utf8.first ?? 0)
    }

    private func clearComposing() {
        composing = ""
        candidates = []
        if usesRime { _ = rime.clear() }
    }

    private func refreshCandidates() {
        candidates = stub.candidates(for: composing)
        refreshStatus()
    }

    private func refreshStatus() {
        if usesRime {
            status = composing.isEmpty ? "Rime 就绪" : "编码：\(composing)"
        } else {
            status = composing.isEmpty
                ? "Rime 未就绪 · 请打开 CyIME App 完成初始化"
                : "编码：\(composing)"
        }
    }

    private func display(_ character: String) -> String {
        switch shiftState {
        case .off: return character
        case .on, .caps: return character.uppercased()
        }
    }

    // MARK: - 布局

    /// 26 键字母行：上滑出数字（q=1 … o=9，p=0），与 CyIME 26 键一致。
    private var letterRows: [[KeySpec]] {
        let row0: [(String, String)] = [
            ("q", "1"), ("w", "2"), ("e", "3"), ("r", "4"), ("t", "5"),
            ("y", "6"), ("u", "7"), ("i", "8"), ("o", "9"), ("p", "0")
        ]
        let row1 = ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
        let row2 = ["z", "x", "c", "v", "b", "n", "m"]

        let shiftedLabels = shiftState == .caps

        var rows: [[KeySpec]] = []

        rows.append(row0.map { letter, digit in
            KeySpec(
                id: "char-\(letter)",
                label: shiftedLabels ? letter.uppercased() : letter,
                action: .character(letter),
                hint: digit,
                swipeUp: .character(digit)
            )
        })

        var second = [KeySpec(id: "spacer-left", label: "", action: .character(""), width: 0.5, isSpacer: true)]
        second += row1.map { letter in
            KeySpec(
                id: "char-\(letter)",
                label: shiftedLabels ? letter.uppercased() : letter,
                action: .character(letter)
            )
        }
        second.append(KeySpec(id: "spacer-right", label: "", action: .character(""), width: 0.5, isSpacer: true))
        rows.append(second)

        var third: [KeySpec] = [
            KeySpec(id: "shift", label: shiftLabel, action: .shift, width: 1.5, isSpecial: true, isAccent: shiftState != .off)
        ]
        third += row2.map { letter in
            KeySpec(
                id: "char-\(letter)",
                label: shiftedLabels ? letter.uppercased() : letter,
                action: .character(letter)
            )
        }
        third.append(KeySpec(id: "delete", label: "⌫", action: .delete, width: 1.5, isSpecial: true))
        rows.append(third)

        rows.append(bottomRow)
        return rows
    }

    private var shiftLabel: String {
        switch shiftState {
        case .off: return "⇧"
        case .on: return "⬆︎"
        case .caps: return "⇪"
        }
    }

    /// 底排：123 / 逗号 / 空格 / 句号 / 地球 / 回车，权重按 CyIME 26 键。
    private var bottomRow: [KeySpec] {
        [
            KeySpec(id: "numbers", label: mode == .numbers ? "ABC" : "123", action: .toggleNumbers, width: 1.2, isSpecial: true),
            KeySpec(id: "comma", label: mode == .chinese ? "，" : ",", action: .character(","), width: 1, swipeUp: .character("'")),
            KeySpec(id: "space", label: mode == .chinese ? "空格" : "space", action: .space, width: 3.9, isSpace: true),
            KeySpec(id: "period", label: mode == .chinese ? "。" : ".", action: .character("."), width: 1, swipeUp: .character("?")),
            KeySpec(id: "globe", label: "🌐", action: .globe, width: 1, isSpecial: true),
            KeySpec(id: "return", label: "⏎", action: .ret, width: 1.7, isAccent: true)
        ]
    }

    private var numberRows: [[KeySpec]] {
        let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        let symbols = ["-", "/", ":", ";", "(", ")", "¥", "&", "@", "\""]

        var thirdRow = [".", ",", "?", "!", "'"].map { character in
            KeySpec(id: "symbol-\(character)", label: character, action: .character(character))
        }
        thirdRow.append(KeySpec(id: "delete", label: "⌫", action: .delete, width: 1.5, isSpecial: true))

        return [
            digits.map { KeySpec(id: "digit-\($0)", label: $0, action: .character($0)) },
            symbols.map { KeySpec(id: "symbol-\($0)", label: $0, action: .character($0)) },
            thirdRow,
            [
                KeySpec(id: "letters", label: "ABC", action: .toggleNumbers, width: 1.2, isSpecial: true),
                KeySpec(id: "space", label: "space", action: .space, width: 3.9, isSpace: true),
                KeySpec(id: "globe", label: "🌐", action: .globe, width: 1, isSpecial: true),
                KeySpec(id: "return", label: "⏎", action: .ret, width: 1.7, isAccent: true)
            ]
        ]
    }
}
