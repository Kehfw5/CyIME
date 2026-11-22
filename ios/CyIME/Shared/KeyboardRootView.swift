import SwiftUI
import UIKit

/// 收集每个按键在键盘坐标系里的位置，供统一手势做命中测试。
private struct KeyFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

@MainActor
struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.colorScheme) private var colorScheme

    // 统一手势状态
    @State private var keyFrames: [String: CGRect] = [:]
    @State private var startKey: KeySpec?
    @State private var startTime: Date?
    @State private var startPoint: CGPoint = .zero
    @State private var pressedID: String?

    @State private var glideActive = false
    @State private var glidePoints: [CGPoint] = []
    @State private var lastPreviewAt: Date = .distantPast

    @State private var spaceAccum: CGFloat = 0
    @State private var spaceLastX: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            CandidateBar(model: model)

            VStack(spacing: 0) {
                ForEach(Array(model.rows.enumerated()), id: \.offset) { item in
                    KeyRow(keys: item.element, pressedID: pressedID)
                }
            }
            .coordinateSpace(name: "keyboard")
            .onPreferenceChange(KeyFramePreferenceKey.self) { keyFrames = $0 }
            .gesture(keyboardGesture)
        }
        .padding(.vertical, 4)
        .background(keyboardBackground)
    }

    // MARK: - 统一手势

    private var keyboardGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if startKey == nil {
                    beginTouch(at: value.startLocation)
                }
                guard let key = startKey else { return }

                if key.isSpace {
                    handleSpaceDrag(value.translation.width)
                }

                trackGlide(key: key, value: value)
            }
            .onEnded { value in
                endTouch(value: value)
            }
    }

    private func beginTouch(at point: CGPoint) {
        startPoint = point
        startTime = Date()
        let key = keySpec(at: point)
        startKey = key
        pressedID = key?.id
        glideActive = false
        glidePoints = []
        lastPreviewAt = .distantPast
        spaceAccum = 0
        spaceLastX = 0

        if key?.action == .delete {
            model.beginDeleteRepeat()
        }
    }

    private func endTouch(value: DragGesture.Value) {
        model.endDeleteRepeat()
        let key = startKey
        let startedAt = startTime

        defer {
            startKey = nil
            startTime = nil
            pressedID = nil
            glideActive = false
            glidePoints = []
        }
        guard let key else { return }

        if glideActive {
            let (xs, ys) = glideArrays(glidePoints)
            model.glideFinish(xs: xs, ys: ys, keyUnit: letterKeyUnit, centers: letterCenters)
            return
        }

        let dx = value.translation.width
        let dy = value.translation.height
        let held = Date().timeIntervalSince(startedAt ?? Date())

        if abs(dx) < 16, abs(dy) < 16 {
            // 长按删除已连删时不再补一次。
            if key.action == .delete, held >= 0.4 { return }
            model.tap(key.action)
        } else if dy < -14, abs(dx) < 40, let up = key.swipeUp {
            model.tap(up)
        } else if dy > 14, abs(dx) < 40, let down = key.swipeDown {
            model.tap(down)
        }
    }

    private func handleSpaceDrag(_ x: CGFloat) {
        spaceAccum += x - spaceLastX
        spaceLastX = x
        while abs(spaceAccum) >= 12 {
            let step = spaceAccum > 0 ? 1 : -1
            model.moveCursorBy(step)
            spaceAccum -= CGFloat(step) * 12
        }
    }

    // MARK: - 滑行

    private func trackGlide(key: KeySpec, value: DragGesture.Value) {
        guard key.id.hasPrefix("char-") else { return }

        if !glideActive {
            let dist = (value.translation.width * value.translation.width
                        + value.translation.height * value.translation.height).squareRoot()
            guard dist > 30 else { return }
            glideActive = true
            glidePoints = [startPoint]
        }

        glidePoints.append(value.location)
        if glidePoints.count > 400 { glidePoints.removeFirst(200) }

        let now = Date()
        if now.timeIntervalSince(lastPreviewAt) > 0.15, glidePoints.count >= 4 {
            lastPreviewAt = now
            let (xs, ys) = glideArrays(glidePoints)
            model.glidePreview(xs: xs, ys: ys, keyUnit: letterKeyUnit, centers: letterCenters)
        }
    }

    private func glideArrays(_ points: [CGPoint]) -> ([Float], [Float]) {
        (points.map { Float($0.x) }, points.map { Float($0.y) })
    }

    /// 字母键中心（与轨迹同一坐标系）。
    private var letterCenters: [Character: (x: Float, y: Float)] {
        var centers: [Character: (x: Float, y: Float)] = [:]
        for (id, rect) in keyFrames where id.hasPrefix("char-") {
            if let letter = id.dropFirst(5).first {
                centers[letter] = (Float(rect.midX), Float(rect.midY))
            }
        }
        return centers
    }

    private var letterKeyUnit: Float {
        var widths: [Float] = []
        for (id, rect) in keyFrames where id.hasPrefix("char-") {
            widths.append(Float(rect.width))
        }
        guard !widths.isEmpty else { return 0 }
        widths.sort()
        return widths[widths.count / 2]
    }

    private func keySpec(at point: CGPoint) -> KeySpec? {
        for (id, rect) in keyFrames where rect.contains(point) {
            if let spec = specsByID[id] { return spec }
        }
        return nil
    }

    private var specsByID: [String: KeySpec] {
        var map: [String: KeySpec] = [:]
        for row in model.rows {
            for key in row where !key.isSpacer {
                map[key.id] = key
            }
        }
        return map
    }

    private var keyboardBackground: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(
                Color(uiColor: .systemBackground)
                    .opacity(colorScheme == .dark ? 0.35 : 0.55)
            )
        }
        .ignoresSafeArea()
    }
}

private struct KeyRow: View {
    let keys: [KeySpec]
    let pressedID: String?

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 5) {
                ForEach(keys) { key in
                    if key.isSpacer {
                        Color.clear
                            .frame(width: width(for: key, totalWidth: geometry.size.width))
                    } else {
                        KeyButton(key: key, isPressed: pressedID == key.id)
                            .frame(width: width(for: key, totalWidth: geometry.size.width))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 44)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
    }

    private func width(for key: KeySpec, totalWidth: CGFloat) -> CGFloat {
        let spacing = CGFloat(max(keys.count - 1, 0)) * 5
        let totalWeight = keys.reduce(CGFloat.zero) { $0 + $1.width }
        guard totalWeight > 0 else { return 0 }
        return max(0, (totalWidth - spacing) * key.width / totalWeight)
    }
}

/// 纯展示键帽：手势统一由键盘容器处理，这里不挂任何手势。
private struct KeyButton: View {
    let key: KeySpec
    let isPressed: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(key.label)
                .font(.system(size: fontSize, weight: key.isSpecial ? .medium : .regular))
                .foregroundStyle(labelColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let hint = key.hint {
                Text(hint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
                    .padding(.trailing, 5)
            }
        }
        .background(
            fill,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: KeyFramePreferenceKey.self,
                    value: [key.id: proxy.frame(in: .named("keyboard"))]
                )
            }
        )
        .shadow(color: .black.opacity(0.07), radius: 1, x: 0, y: 1)
        .scaleEffect(isPressed ? 0.94 : 1)
        .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    private var fontSize: CGFloat {
        switch key.action {
        case .space: return 15
        case .globe: return 18
        default:
            if key.isCompact { return 16 }
            return key.isSpecial ? 14 : 20
        }
    }

    private var labelColor: Color {
        if key.isAccent && !key.isSpecial { return .white }
        if key.isAccent { return .accentColor }
        return .primary
    }

    private var fill: Color {
        if key.isAccent && !key.isSpecial { return .accentColor.opacity(0.85) }
        if key.isSpecial { return Color(uiColor: .tertiarySystemFill) }
        return Color(uiColor: .secondarySystemBackground).opacity(0.75)
    }
}

private struct CandidateBar: View {
    @ObservedObject var model: KeyboardModel
    var body: some View {
        HStack(spacing: 6) {
            if !model.composing.isEmpty {
                Text(model.composing)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(model.candidates.enumerated()), id: \.offset) { index, candidate in
                            Button {
                                model.selectCandidate(at: index)
                            } label: {
                                Text(candidate)
                                    .font(.system(size: 17))
                                    .padding(.horizontal, 10)
                                    .frame(height: 34)
                                    .background(
                                        Color(uiColor: .secondarySystemBackground).opacity(0.9),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button { model.pageUp() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)

                Button { model.pageDown() } label: {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            } else {
                Text(model.status)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Button {
                    model.tap(.toggleMode)
                } label: {
                    Text(model.modeLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 8)
                        .frame(height: 28)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    model.tap(.dismiss)
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 46)
    }
}
