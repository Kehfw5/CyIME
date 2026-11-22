import Combine
import CoreGraphics
import Foundation

enum InputMode: String, Equatable {
    case chinese = "中"
    case english = "英"
    case numbers = "123"
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
}

/// M0 的占位中文引擎：只验证候选栏、编码、上屏流程。
/// M1 会替换成真正由 librime 提供的候选。
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
        if let exact = table[key] {
            return exact
        }

        var seen = Set<String>()
        var result: [String] = []
        for (_, words) in table
            .filter({ $0.key.hasPrefix(key) })
            .sorted(by: { $0.key.count < $1.key.count }) {
            for word in words where seen.insert(word).inserted {
                result.append(word)
            }
        }

        if result.isEmpty {
            return [composing]
        }
        return Array(result.prefix(12))
    }
}

@MainActor
final class KeyboardModel: ObservableObject {
    @Published private(set) var mode: InputMode = .chinese
    @Published private(set) var isShifted = false
    @Published private(set) var composing = ""
    @Published private(set) var candidates: [String] = []
    @Published private(set) var status = "M0 最小键盘 · Rime 未接入"
    @Published private(set) var hasText = false

    private let insertText: (String) -> Void
    private let deleteBackward: () -> Void
    private let advanceInputMode: () -> Void
    private let dismissKeyboard: () -> Void
    private let engine = StubChineseEngine()

    init(
        insertText: @escaping (String) -> Void,
        deleteBackward: @escaping () -> Void,
        advanceInputMode: @escaping () -> Void,
        dismissKeyboard: @escaping () -> Void
    ) {
        self.insertText = insertText
        self.deleteBackward = deleteBackward
        self.advanceInputMode = advanceInputMode
        self.dismissKeyboard = dismissKeyboard
    }

    var modeLabel: String { mode.rawValue }

    var rows: [[KeySpec]] {
        mode == .numbers ? numberRows : letterRows
    }

    func tap(_ action: KeyAction) {
        switch action {
        case .character(let value):
            switch mode {
            case .chinese:
                composing += value.lowercased()
                refreshCandidates()
            case .english:
                insertText(isShifted ? value.uppercased() : value)
                if isShifted { isShifted = false }
            case .numbers:
                insertText(value)
            }
        case .shift:
            isShifted.toggle()
        case .delete:
            if composing.isEmpty {
                deleteBackward()
            } else {
                composing.removeLast()
                refreshCandidates()
            }
        case .space:
            if !composing.isEmpty, let first = candidates.first {
                commitCandidate(first)
            } else {
                insertText(" ")
            }
        case .ret:
            if composing.isEmpty {
                insertText("\n")
            } else {
                commitCandidate(composing)
            }
        case .globe:
            advanceInputMode()
        case .toggleMode:
            switch mode {
            case .chinese:
                mode = .english
            case .english:
                mode = .chinese
            case .numbers:
                mode = .chinese
            }
            clearComposing()
            status = "模式：\(modeLabel)"
        case .toggleNumbers:
            mode = mode == .numbers ? .chinese : .numbers
            clearComposing()
            status = "模式：\(modeLabel)"
        case .dismiss:
            dismissKeyboard()
        }
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

    private func clearComposing() {
        composing = ""
        candidates = []
    }

    private func refreshCandidates() {
        candidates = engine.candidates(for: composing)
        status = composing.isEmpty ? "M0 最小键盘 · Rime 未接入" : "编码：\(composing)"
    }

    private func display(_ character: String) -> String {
        isShifted ? character.uppercased() : character
    }

    private var letterRows: [[KeySpec]] {
        let rows: [[String]] = [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
            ["z", "x", "c", "v", "b", "n", "m"]
        ]

        var result = rows.enumerated().map { index, row -> [KeySpec] in
            var keys = row.map { character in
                KeySpec(
                    id: "char-\(character)",
                    label: display(character),
                    action: .character(character)
                )
            }

            switch index {
            case 1:
                keys.insert(
                    KeySpec(id: "spacer-left", label: "", action: .character(""), width: 0.5, isSpacer: true),
                    at: 0
                )
                keys.append(
                    KeySpec(id: "spacer-right", label: "", action: .character(""), width: 0.5, isSpacer: true)
                )
            case 2:
                keys.insert(
                    KeySpec(id: "shift", label: "⇧", action: .shift, width: 1.4, isSpecial: true),
                    at: 0
                )
                keys.append(
                    KeySpec(id: "delete", label: "⌫", action: .delete, width: 1.4, isSpecial: true)
                )
            default:
                break
            }

            return keys
        }

        result.append([
            KeySpec(id: "numbers", label: "123", action: .toggleNumbers, width: 1.2, isSpecial: true),
            KeySpec(id: "globe", label: "🌐", action: .globe, width: 1.2, isSpecial: true),
            KeySpec(id: "space", label: mode == .chinese ? "空格" : "space", action: .space, width: 4.2),
            KeySpec(id: "return", label: "⏎", action: .ret, width: 1.6, isAccent: true)
        ])

        return result
    }

    private var numberRows: [[KeySpec]] {
        let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        let symbols = ["-", "/", ":", ";", "(", ")", "¥", "&", "@", "\""]

        var thirdRow = [".", ",", "?", "!", "'"].map { character in
            KeySpec(id: "symbol-\(character)", label: character, action: .character(character))
        }
        thirdRow.append(
            KeySpec(id: "delete", label: "⌫", action: .delete, width: 1.4, isSpecial: true)
        )

        return [
            digits.map { KeySpec(id: "digit-\($0)", label: $0, action: .character($0)) },
            symbols.map { KeySpec(id: "symbol-\($0)", label: $0, action: .character($0)) },
            thirdRow,
            [
                KeySpec(id: "letters", label: "ABC", action: .toggleNumbers, width: 1.2, isSpecial: true),
                KeySpec(id: "globe", label: "🌐", action: .globe, width: 1.2, isSpecial: true),
                KeySpec(id: "space", label: "space", action: .space, width: 4.2),
                KeySpec(id: "return", label: "⏎", action: .ret, width: 1.6, isAccent: true)
            ]
        ]
    }
}
