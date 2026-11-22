import Foundation

/// 一笔滑行的候选。[cost] 含词频先验，用于排序；[shape] 只含轨迹代价。
struct GlideCandidate {
    let word: String
    let cost: Float
    let shape: Float
    let listed: Bool
}

/// 参与滑行识别的键盘：键宽（单位）与每个字母键的中心（同一坐标系）。
struct GlideKeyboard {
    let keyUnit: Float
    let centers: [Character: (x: Float, y: Float)]

    /// 布局签名：键位量化到 1/8 键宽，用于复用已建模板。
    var revision: Int {
        var hash = 17
        for key in centers.keys.sorted() {
            guard let point = centers[key] else { continue }
            hash = 31 * (31 * (31 * hash + Int(key.asciiValue ?? 0)) + Int(point.x / keyUnit * 8)) + Int(point.y / keyUnit * 8)
        }
        return hash
    }
}

// MARK: - 重采样

private func distance(_ ax: Float, _ ay: Float, _ bx: Float, _ by: Float) -> Float {
    let dx = ax - bx
    let dy = ay - by
    return (dx * dx + dy * dy).squareRoot()
}

private func pathLength(_ xs: [Float], _ ys: [Float]) -> Float {
    guard xs.count > 1 else { return 0 }
    var total: Float = 0
    for i in 1..<xs.count { total += distance(xs[i], ys[i], xs[i - 1], ys[i - 1]) }
    return total
}

/// 按弧长等距取 count 点；单点重复同一点。
private func resampleArcLength(_ xs: [Float], _ ys: [Float], count: Int) -> ([Float], [Float]) {
    var outX = [Float](repeating: 0, count: count)
    var outY = [Float](repeating: 0, count: count)
    guard xs.count > 1 else {
        outX = [Float](repeating: xs.first ?? 0, count: count)
        outY = [Float](repeating: ys.first ?? 0, count: count)
        return (outX, outY)
    }
    var cumulative = [Float](repeating: 0, count: xs.count)
    for i in 1..<xs.count {
        cumulative[i] = cumulative[i - 1] + distance(xs[i], ys[i], xs[i - 1], ys[i - 1])
    }
    let total = cumulative[cumulative.count - 1]
    if total <= 0 {
        outX = [Float](repeating: xs[0], count: count)
        outY = [Float](repeating: ys[0], count: count)
        return (outX, outY)
    }
    var segment = 1
    for sample in 0..<count {
        let target = total * Float(sample) / Float(count - 1)
        while segment < xs.count - 1 && cumulative[segment] < target { segment += 1 }
        let length = cumulative[segment] - cumulative[segment - 1]
        let fraction: Float = length <= 0 ? 0 : min(max((target - cumulative[segment - 1]) / length, 0), 1)
        outX[sample] = xs[segment - 1] + fraction * (xs[segment] - xs[segment - 1])
        outY[sample] = ys[segment - 1] + fraction * (ys[segment] - ys[segment - 1])
    }
    return (outX, outY)
}

// MARK: - 解码器

/// 移植自 Android CyIME 的 GlideDecoder：把轨迹与"词经过各字母键中心"的折线比较，
/// 端点筛选 + LB_Keogh 下界 + 带宽 DTW + 词频先验。
final class GlideDecoder {
    static let samples = 32
    static let maxWord = 20
    static let minPathKeys: Float = 0.75
    static let maxEndpoint: Float = 1.0
    static let maxShape: Float = 1.0
    static let endpointWeight: Float = 0.35
    static let priorWeight: Float = 0.2
    static let unlistedPrior: Float = 1.5
    static let syllableRankCost: Float = 0.05
    private static let boundSlack: Float = 1e-4
    private static let band = samples / 4

    let keyboard: GlideKeyboard
    var revision: Int { keyboard.revision }

    private var words: [String] = []
    private var shapes: [String] = []
    private var priors: [Float] = []
    private var templateX: [Float] = []
    private var templateY: [Float] = []
    private var startX: [Float] = []
    private var startY: [Float] = []
    private var endX: [Float] = []
    private var endY: [Float] = []
    private var known = Set<String>()
    private var syllableGlide: SyllableGlide?

    var size: Int { words.count }

    init(keyboard: GlideKeyboard, words inputWords: [String], syllables: [String]? = nil) {
        self.keyboard = keyboard
        if let syllables {
            self.syllableGlide = SyllableGlide(keyboard: keyboard, syllables: syllables)
        }
        build(inputWords)
    }

    private func build(_ inputWords: [String]) {
        let count = max(inputWords.count, 1)
        let logMax = Float(log(Double(count) + 1))
        var w: [String] = []
        var s: [String] = []
        var p: [Float] = []
        var tx: [Float] = []
        var ty: [Float] = []
        let unit = keyboard.keyUnit
        w.reserveCapacity(inputWords.count)
        s.reserveCapacity(inputWords.count)
        p.reserveCapacity(inputWords.count)
        tx.reserveCapacity(inputWords.count * Self.samples)
        ty.reserveCapacity(inputWords.count * Self.samples)

        for (rank, word) in inputWords.enumerated() {
            let letters = Array(word)
            guard !letters.isEmpty, letters.count <= Self.maxWord else { continue }
            var compact: [Character] = []
            var centersX: [Float] = []
            var centersY: [Float] = []
            var valid = true
            for letter in letters where keyboard.centers[letter] == nil { valid = false }
            guard valid else { continue }
            for letter in letters where compact.last != letter {
                compact.append(letter)
                if let point = keyboard.centers[letter] {
                    centersX.append(point.x / unit)
                    centersY.append(point.y / unit)
                }
            }
            guard !compact.isEmpty else { continue }
            let (rx, ry) = resampleArcLength(centersX, centersY, count: Self.samples)
            w.append(word)
            s.append(String(compact))
            p.append(Float(log(Double(rank) + 2)) / logMax)
            tx.append(contentsOf: rx)
            ty.append(contentsOf: ry)
        }

        words = w
        shapes = s
        priors = p
        templateX = tx
        templateY = ty
        known = Set(w)
        startX = (0..<w.count).map { templateX[$0 * Self.samples] }
        startY = (0..<w.count).map { templateY[$0 * Self.samples] }
        endX = (0..<w.count).map { templateX[$0 * Self.samples + Self.samples - 1] }
        endY = (0..<w.count).map { templateY[$0 * Self.samples + Self.samples - 1] }
    }

    /// xs/ys 为与键中心同一坐标系的轨迹点。轨迹过短或无接近词时返回空。
    func decode(xs: [Float], ys: [Float], limit: Int = 6) -> [GlideCandidate] {
        guard xs.count >= 2, xs.count == ys.count else { return [] }
        let unit = keyboard.keyUnit
        let qx = xs.map { $0 / unit }
        let qy = ys.map { $0 / unit }
        guard pathLength(qx, qy) >= Self.minPathKeys else { return [] }

        let (sx, sy) = resampleArcLength(qx, qy, count: Self.samples)
        let envelope = Envelope(xs: sx, ys: sy)
        let last = Self.samples - 1
        let near = Self.maxEndpoint * Self.maxEndpoint * 1.001

        struct Reachable {
            let index: Int
            let endpoints: Float
            let least: Float
        }
        var reachable: [Reachable] = []
        reachable.reserveCapacity(256)

        let n = words.count
        let sx0 = sx[0], sy0 = sy[0], sxl = sx[last], syl = sy[last]
        for index in 0..<n {
            let ax = sx0 - startX[index], ay = sy0 - startY[index]
            if ax * ax + ay * ay > near { continue }
            let bx = sxl - endX[index], by = syl - endY[index]
            if bx * bx + by * by > near { continue }
            let start = distance(sx0, sy0, templateX[index * Self.samples], templateY[index * Self.samples])
            if start > Self.maxEndpoint { continue }
            let end = distance(sxl, syl, templateX[index * Self.samples + last], templateY[index * Self.samples + last])
            if end > Self.maxEndpoint { continue }
            let lower = envelope.lowerBound(
                bx: Array(templateX[(index * Self.samples)..<((index + 1) * Self.samples)]),
                by: Array(templateY[(index * Self.samples)..<((index + 1) * Self.samples)]),
                start: start, end: end
            )
            if lower > Self.maxShape + Self.boundSlack { continue }
            let endpoints = (start + end) / 2 * Self.endpointWeight
            reachable.append(Reachable(index: index, endpoints: endpoints,
                                       least: endpoints + priors[index] * Self.priorWeight + lower))
        }

        reachable.sort { $0.least < $1.least }
        var results: [GlideCandidate] = []
        var shapeCache: [String: Float] = [:]
        var kept: [Float] = []

        for item in reachable {
            if kept.count >= limit, item.least > (kept.last ?? .greatestFiniteMagnitude) + Self.boundSlack { break }
            let index = item.index
            let fixed = item.endpoints + priors[index] * Self.priorWeight
            let bound: Float = kept.count < limit ? Self.maxShape : min(Self.maxShape, (kept.last ?? 0) - fixed)
            let shapeKey = shapes[index]
            let shape: Float
            if let cached = shapeCache[shapeKey] {
                shape = cached
            } else {
                shape = dtw(sx, sy,
                            Array(templateX[(index * Self.samples)..<((index + 1) * Self.samples)]),
                            Array(templateY[(index * Self.samples)..<((index + 1) * Self.samples)]),
                            bound: bound)
                shapeCache[shapeKey] = shape
            }
            if shape > Self.maxShape { continue }
            let geometry = shape + item.endpoints
            let cost = geometry + priors[index] * Self.priorWeight
            results.append(GlideCandidate(word: words[index], cost: cost, shape: geometry, listed: true))
            kept.append(cost)
            kept.sort(by: >)
            if kept.count > limit { kept.removeLast() }
        }

        // 音节识别出的、词表外的编码。词表已给够候选时跳过（维特比较慢，实时预览优先流畅）。
        if let syllableGlide, results.count < limit {
            for (rank, code) in syllableGlide.decode(xs: xs, ys: ys).enumerated() {
                if known.contains(code) || code.count > Self.maxWord { continue }
                let compact = Array(code)
                guard compact.count >= 2 else { continue }
                var centersX: [Float] = []
                var centersY: [Float] = []
                var valid = true
                for letter in compact {
                    if let point = keyboard.centers[letter] {
                        centersX.append(point.x / unit)
                        centersY.append(point.y / unit)
                    } else { valid = false }
                }
                if !valid { continue }
                let shapeKey = String(compact)
                if results.contains(where: { $0.word == shapeKey }) { continue }
                let (tx, ty) = resampleArcLength(centersX, centersY, count: Self.samples)
                let start = distance(sx[0], sy[0], tx[0], ty[0])
                let end = distance(sx[last], sy[last], tx[last], ty[last])
                if start > Self.maxEndpoint || end > Self.maxEndpoint { continue }
                let shape: Float
                if let cached = shapeCache[shapeKey] { shape = cached }
                else {
                    shape = dtw(sx, sy, tx, ty)
                    shapeCache[shapeKey] = shape
                }
                if shape > Self.maxShape { continue }
                let geometry = shape + (start + end) / 2 * Self.endpointWeight
                results.append(GlideCandidate(
                    word: code,
                    cost: geometry + Self.unlistedPrior * Self.priorWeight + Float(rank) * Self.syllableRankCost,
                    shape: geometry,
                    listed: false
                ))
            }
        }

        results.sort { $0.cost == $1.cost ? $0.word < $1.word : $0.cost < $1.cost }
        return Array(results.prefix(limit))
    }

    // MARK: DTW / 下界

    private struct Envelope {
        private var minX = [Float](repeating: 0, count: GlideDecoder.samples)
        private var maxX = [Float](repeating: 0, count: GlideDecoder.samples)
        private var minY = [Float](repeating: 0, count: GlideDecoder.samples)
        private var maxY = [Float](repeating: 0, count: GlideDecoder.samples)

        init(xs: [Float], ys: [Float]) {
            let band = GlideDecoder.samples / 4
            for j in 0..<GlideDecoder.samples {
                var x0 = Float.greatestFiniteMagnitude
                var x1 = -Float.greatestFiniteMagnitude
                var y0 = Float.greatestFiniteMagnitude
                var y1 = -Float.greatestFiniteMagnitude
                for i in max(0, j - band)...min(GlideDecoder.samples - 1, j + band) {
                    x0 = min(x0, xs[i]); x1 = max(x1, xs[i])
                    y0 = min(y0, ys[i]); y1 = max(y1, ys[i])
                }
                minX[j] = x0; maxX[j] = x1; minY[j] = y0; maxY[j] = y1
            }
        }

        func lowerBound(bx: [Float], by: [Float], start: Float, end: Float) -> Float {
            var sum = start + end
            for j in 1..<(GlideDecoder.samples - 1) {
                let dx = bx[j] < minX[j] ? minX[j] - bx[j] : (bx[j] > maxX[j] ? bx[j] - maxX[j] : 0)
                let dy = by[j] < minY[j] ? minY[j] - by[j] : (by[j] > maxY[j] ? by[j] - maxY[j] : 0)
                if dx != 0 || dy != 0 { sum += (dx * dx + dy * dy).squareRoot() }
            }
            return sum / Float(GlideDecoder.samples)
        }
    }

    private func dtw(_ ax: [Float], _ ay: [Float], _ bx: [Float], _ by: [Float],
                     bound: Float = GlideDecoder.maxShape) -> Float {
        let n = Self.samples
        let band = max(1, Self.band)
        var previous = [Float](repeating: .greatestFiniteMagnitude, count: n + 1)
        var current = [Float](repeating: .greatestFiniteMagnitude, count: n + 1)
        previous[0] = 0
        for i in 1...n {
            for k in 0...n { current[k] = .greatestFiniteMagnitude }
            var rowMin = Float.greatestFiniteMagnitude
            let low = max(1, i - band)
            let high = min(n, i + band)
            if low <= high {
                for j in low...high {
                    let d = distance(ax[i - 1], ay[i - 1], bx[j - 1], by[j - 1])
                    current[j] = d + min(previous[j - 1], min(previous[j], current[j - 1]))
                    if current[j] < rowMin { rowMin = current[j] }
                }
            }
            if rowMin > bound * Float(n) { return .greatestFiniteMagnitude }
            swap(&previous, &current)
        }
        return previous[n] / Float(n)
    }
}

// MARK: - 音节维特比（中文）

/// 移植自 Android 的 SyllableGlide：把轨迹按「命中键 + 直线段」切成合法音节，
/// 用维特比求代价最小的若干编码（用于词表里没有的连划）。
final class SyllableGlide {
    private static let step: Float = 0.25
    private static let maxPoints = 120
    private static let hitRadius: Float = 1.0
    private static let hitWeight: Float = 1.5
    private static let segmentWeight: Float = 1.5
    private static let keyCost: Float = 0.45
    private static let repeatCost: Float = 0.6
    private static let detourWeight: Float = 3.0
    private static let syllableCostBase: Float = 0.2
    private static let syllablePrior: Float = 0.6
    private static let straightTolerance: Float = 0.5

    private let keyboard: GlideKeyboard
    private var nodeChar: [Character] = [" "]
    private var nodeChildren: [[Character: Int]] = [[:]]
    private var nodeCost: [Float] = [.nan]

    private let keys: [Character]
    private let keyX: [Float]
    private let keyY: [Float]

    init(keyboard: GlideKeyboard, syllables: [String]) {
        self.keyboard = keyboard
        keys = keyboard.centers.keys.sorted()
        keyX = keys.map { keyboard.centers[$0]!.x / keyboard.keyUnit }
        keyY = keys.map { keyboard.centers[$0]!.y / keyboard.keyUnit }

        var distinct: [String] = []
        var seen = Set<String>()
        for syllable in syllables where !syllable.isEmpty {
            if syllable.contains(where: { keyboard.centers[$0] == nil }) { continue }
            if seen.insert(syllable).inserted { distinct.append(syllable) }
        }
        let logMax = Float(log(Double(distinct.count) + 1))
        for (rank, syllable) in distinct.enumerated() {
            var node = 0
            for character in syllable {
                if let next = nodeChildren[node][character] {
                    node = next
                } else {
                    nodeChar.append(character)
                    nodeChildren.append([:])
                    nodeCost.append(.nan)
                    let newIndex = nodeChar.count - 1
                    nodeChildren[node][character] = newIndex
                    node = newIndex
                }
            }
            if nodeCost[node].isNaN {
                nodeCost[node] = Self.syllableCostBase
                    + Self.syllablePrior * Float(log(Double(rank) + 2)) / logMax
            }
        }
    }

    func decode(xs: [Float], ys: [Float], limit: Int = 3) -> [String] {
        guard xs.count >= 2, xs.count == ys.count else { return [] }
        let unit = keyboard.keyUnit
        let rawX = xs.map { $0 / unit }
        let rawY = ys.map { $0 / unit }
        let (px, py) = Self.resampleByStep(rawX, rawY)
        let n = px.count
        guard n >= 2 else { return [] }
        let total = Self.pathLength(px, py)
        let step = total / Float(n - 1)

        var nearKeys = [[Int]](repeating: [], count: n)
        for i in 0..<n {
            var list: [Int] = []
            for k in keys.indices where Self.dist(px[i], py[i], keyX[k], keyY[k]) <= Self.hitRadius {
                list.append(k)
            }
            nearKeys[i] = list
        }

        var straightUntil = [Int](repeating: 0, count: n)
        for i in 0..<n {
            var j = i + 1
            while j < n && Self.maxDeviation(px, py, i, j) <= Self.straightTolerance
                && Float(j - i) * step - Self.dist(px[i], py[i], px[j], py[j]) <= Self.straightTolerance {
                j += 1
            }
            straightUntil[i] = j - 1
        }

        let nodes = nodeChar.count
        var cost = [[Float]](repeating: [Float](repeating: .greatestFiniteMagnitude, count: nodes), count: n)
        var fromI = [[Int]](repeating: [Int](repeating: -1, count: nodes), count: n)
        var fromNode = [[Int]](repeating: [Int](repeating: -1, count: nodes), count: n)

        for k in nearKeys[0] {
            guard let node = nodeChildren[0][keys[k]] else { continue }
            let value = Self.hitWeight * Self.dist(px[0], py[0], keyX[k], keyY[k])
            if value < cost[0][node] { cost[0][node] = value }
        }

        func keyIndexOf(_ character: Character) -> Int {
            keys.firstIndex(of: character) ?? -1
        }

        func update(_ i: Int, _ node: Int, _ j: Int, _ target: Int, _ value: Float) {
            if value < cost[j][target] {
                cost[j][target] = value
                fromI[j][target] = i
                fromNode[j][target] = node
            }
        }

        func relax(_ i: Int, _ node: Int, _ j: Int, _ next: Int, _ value: Float) {
            let character = keys[next]
            if let target = nodeChildren[node][character] {
                update(i, node, j, target, value)
            }
            if !nodeCost[node].isNaN, let target = nodeChildren[0][character] {
                update(i, node, j, target, value + nodeCost[node])
            }
        }

        for i in 0..<n {
            for node in 1..<nodes where cost[i][node].isFinite {
                let here = cost[i][node]
                let k = keyIndexOf(nodeChar[node])
                if k >= 0 {
                    relax(i, node, i, k, here + Self.keyCost + Self.repeatCost)
                }
            }
            for node in 1..<nodes where cost[i][node].isFinite {
                let here = cost[i][node]
                let k = keyIndexOf(nodeChar[node])
                guard k >= 0 else { continue }
                var j = i + 1
                while j <= straightUntil[i] {
                    for next in nearKeys[j] where next != k {
                        let value = here
                            + Self.segmentCost(px, py, i, j, k, next, keyX, keyY, step)
                            + Self.keyCost
                            + Self.hitWeight * Self.dist(px[j], py[j], keyX[next], keyY[next])
                        relax(i, node, j, next, value)
                    }
                    j += 1
                }
            }
        }

        let last = n - 1
        var ends: [Int] = []
        for node in 0..<nodes where !nodeCost[node].isNaN && cost[last][node].isFinite {
            ends.append(node)
        }
        ends.sort { cost[last][$0] + nodeCost[$0] < cost[last][$1] + nodeCost[$1] }

        var codes: [String] = []
        var seenCodes = Set<String>()
        for end in ends {
            var letters: [Character] = []
            var i = last
            var node = end
            while node > 0 {
                letters.append(nodeChar[node])
                let previousI = fromI[i][node]
                let previousNode = fromNode[i][node]
                if previousI < 0 { break }
                i = previousI
                node = previousNode
            }
            let code = String(letters.reversed())
            if seenCodes.insert(code).inserted { codes.append(code) }
            if codes.count >= limit { break }
        }
        return codes
    }

    // MARK: helpers

    private static func dist(_ ax: Float, _ ay: Float, _ bx: Float, _ by: Float) -> Float {
        let dx = ax - bx, dy = ay - by
        return (dx * dx + dy * dy).squareRoot()
    }

    private static func pointToSegment(_ x: Float, _ y: Float, _ ax: Float, _ ay: Float, _ bx: Float, _ by: Float) -> Float {
        let vx = bx - ax, vy = by - ay
        let length = vx * vx + vy * vy
        let t: Float = length <= 0 ? 0 : min(max(((x - ax) * vx + (y - ay) * vy) / length, 0), 1)
        return dist(x, y, ax + t * vx, ay + t * vy)
    }

    private static func pathLength(_ xs: [Float], _ ys: [Float]) -> Float {
        guard xs.count > 1 else { return 0 }
        var total: Float = 0
        for i in 1..<xs.count { total += dist(xs[i - 1], ys[i - 1], xs[i], ys[i]) }
        return total
    }

    private static func maxDeviation(_ px: [Float], _ py: [Float], _ i: Int, _ j: Int) -> Float {
        var worst: Float = 0
        if j > i + 1 {
            for m in (i + 1)..<j {
                worst = max(worst, pointToSegment(px[m], py[m], px[i], py[i], px[j], py[j]))
            }
        }
        return worst
    }

    private static func segmentCost(_ px: [Float], _ py: [Float], _ i: Int, _ j: Int,
                                    _ a: Int, _ b: Int,
                                    _ keyX: [Float], _ keyY: [Float], _ step: Float) -> Float {
        var sum: Float = 0
        if j > i + 1 {
            for m in (i + 1)..<j {
                sum += pointToSegment(px[m], py[m], keyX[a], keyY[a], keyX[b], keyY[b])
            }
        }
        let detour = max(Float(j - i) * step - dist(px[i], py[i], px[j], py[j]), 0)
        return segmentWeight * sum * step + detourWeight * detour
    }

    private static func resampleByStep(_ xs: [Float], _ ys: [Float]) -> ([Float], [Float]) {
        let total = pathLength(xs, ys)
        let step = max(Self.step, total / Float(maxPoints - 1))
        let count = max(2, Int(total / step) + 1)
        return GlideDecoderResampler.resample(xs, ys, count: count)
    }
}

/// 暴露给 SyllableGlide 的重采样（与 GlideDecoder 同一实现）。
enum GlideDecoderResampler {
    static func resample(_ xs: [Float], _ ys: [Float], count: Int) -> ([Float], [Float]) {
        resampleArcLength(xs, ys, count: count)
    }
}
