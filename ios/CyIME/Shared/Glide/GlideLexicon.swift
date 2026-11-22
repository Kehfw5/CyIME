import Foundation

/// 随包的滑行词表：中文为「音节编码 + 对应最常用词」，英文为按词频排序的词表。
/// 数据文件由 Xcode 构建阶段从 `app/src/main/assets` 拷进扩展的 `GlideData/`。
final class GlideLexicon {
    static let shared = GlideLexicon()

    private var chineseEntries: [[String]]?
    private var chineseAlignedWords: [String]?
    private var chineseCodeList: [String]?
    private var chineseCodeWord: [String: String]?
    private var chineseSyllables: [String]?

    private var englishWordList: [String]?

    private var chineseDecoder: GlideDecoder?
    private var chineseRevision: Int = .min
    private var englishDecoder: GlideDecoder?
    private var englishRevision: Int = .min

    // MARK: 中文

    func chineseCandidates(xs: [Float], ys: [Float], keyboard: GlideKeyboard, limit: Int = 6) -> [GlideCandidate] {
        guard let decoder = chineseDecoder(for: keyboard) else { return [] }
        return decoder.decode(xs: xs, ys: ys, limit: limit)
    }

    func englishCandidates(xs: [Float], ys: [Float], keyboard: GlideKeyboard, limit: Int = 6) -> [GlideCandidate] {
        guard let decoder = englishDecoder(for: keyboard) else { return [] }
        return decoder.decode(xs: xs, ys: ys, limit: limit)
    }

    /// 编码（拼音连写）对应的最常用词；没有时返回 nil。
    func chineseWord(for code: String) -> String? {
        loadChineseIfNeeded()
        return chineseCodeWord?[code]
    }

    private func chineseDecoder(for keyboard: GlideKeyboard) -> GlideDecoder? {
        loadChineseIfNeeded()
        guard let codes = chineseCodeList, !codes.isEmpty else { return nil }
        let revision = keyboard.revision
        if let decoder = chineseDecoder, chineseRevision == revision { return decoder }
        let start = CFAbsoluteTimeGetCurrent()
        let decoder = GlideDecoder(keyboard: keyboard, words: codes, syllables: chineseSyllables)
        chineseDecoder = decoder
        chineseRevision = revision
        AppGroup.appendLog("glide zh templates=\(decoder.size) in \(Int((CFAbsoluteTimeGetCurrent() - start) * 1000))ms")
        return decoder
    }

    private func loadChineseIfNeeded() {
        guard chineseCodeList == nil else { return }
        let start = CFAbsoluteTimeGetCurrent()
        let lines = readLines("glide_pinyin") ?? []
        var entries: [[String]] = []
        entries.reserveCapacity(lines.count)
        var codes: [String] = []
        var codeSeen = Set<String>()
        var codeWord: [String: String] = [:]

        let wordLines = readLines("glide_pinyin_words") ?? []
        for (index, line) in lines.enumerated() {
            let parts = line.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            guard !parts.isEmpty else { continue }
            entries.append(parts)
            let code = parts.joined()
            if codeSeen.insert(code).inserted {
                codes.append(code)
                if index < wordLines.count, !wordLines[index].isEmpty {
                    codeWord[code] = wordLines[index]
                }
            }
        }

        // 音节：先放单字读音（常用在前），再补其它出现过的音节。
        var syllables: [String] = []
        var syllableSeen = Set<String>()
        for entry in entries where entry.count == 1 {
            if syllableSeen.insert(entry[0]).inserted { syllables.append(entry[0]) }
        }
        for entry in entries {
            for syllable in entry where syllableSeen.insert(syllable).inserted {
                syllables.append(syllable)
            }
        }

        chineseEntries = entries
        chineseAlignedWords = wordLines
        chineseCodeList = codes
        chineseCodeWord = codeWord
        chineseSyllables = syllables
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        AppGroup.appendLog("glide zh lexicon codes=\(codes.count) syllables=\(syllables.count) in \(ms)ms")
    }

    // MARK: 英文

    private func englishDecoder(for keyboard: GlideKeyboard) -> GlideDecoder? {
        loadEnglishIfNeeded()
        guard let words = englishWordList, !words.isEmpty else { return nil }
        let revision = keyboard.revision
        if let decoder = englishDecoder, englishRevision == revision { return decoder }
        let start = CFAbsoluteTimeGetCurrent()
        let decoder = GlideDecoder(keyboard: keyboard, words: words)
        englishDecoder = decoder
        englishRevision = revision
        AppGroup.appendLog("glide en templates=\(decoder.size) in \(Int((CFAbsoluteTimeGetCurrent() - start) * 1000))ms")
        return decoder
    }

    private func loadEnglishIfNeeded() {
        guard englishWordList == nil else { return }
        let start = CFAbsoluteTimeGetCurrent()
        var words = (readLines("english") ?? []).filter { !$0.isEmpty }
        // 补充词：每行 "word rank"，按排名插进词表。
        if let extra = readLines("english_glide_words") {
            for line in extra where !line.isEmpty && !line.hasPrefix("#") {
                let parts = line.split(separator: " ").map(String.init)
                guard let word = parts.first, !word.isEmpty else { continue }
                let rank = parts.count > 1 ? (Int(parts[1]) ?? words.count) : words.count
                let index = min(max(rank, 0), words.count)
                words.insert(word, at: index)
            }
        }
        englishWordList = words
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        AppGroup.appendLog("glide en lexicon words=\(words.count) in \(ms)ms")
    }

    // MARK: 读取

    private func readLines(_ name: String) -> [String]? {
        let bundle = Bundle.main
        let url = bundle.url(forResource: name, withExtension: "txt", subdirectory: "GlideData")
            ?? bundle.url(forResource: name, withExtension: "txt")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            AppGroup.appendLog("glide data missing: \(name).txt")
            return nil
        }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
