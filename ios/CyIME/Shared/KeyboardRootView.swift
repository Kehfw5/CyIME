import SwiftUI
import UIKit

/// 收集每个按键在键盘坐标系里的位置，供滑行输入做轨迹→按键命中测试。
private struct KeyFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var keyFrames: [String: CGRect] = [:]
    @State private var trailPoints: [CGPoint] = []

    var body: some View {
        VStack(spacing: 0) {
            CandidateBar(model: model)

            ForEach(Array(model.rows.enumerated()), id: \.offset) { item in
                KeyRow(keys: item.element, model: model)
            }
        }
        .padding(.vertical, 4)
        .background(keyboardBackground)
        .coordinateSpace(name: "keyboard")
        .onPreferenceChange(KeyFramePreferenceKey.self) { keyFrames = $0 }
        .overlay(
            GlideTrailOverlay(points: trailPoints)
                .allowsHitTesting(false)
        )
        .simultaneousGesture(glideGesture)
    }

    /// 滑行：记录手指轨迹，抬手时把划过的字母拼成编码交给 Rime 预览。
    private var glideGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard model.mode == .chinese else { return }
                trailPoints.append(value.location)
                if trailPoints.count > 300 {
                    trailPoints.removeFirst(150)
                }
            }
            .onEnded { value in
                let points = trailPoints
                trailPoints = []
                guard model.mode == .chinese, points.count >= 3 else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                let moved = (dx * dx + dy * dy).squareRoot()
                guard moved > 60 else { return }
                let code = glideCode(from: points)
                if code.count >= 2 {
                    model.performGlide(code: code)
                }
            }
    }

    private func glideCode(from points: [CGPoint]) -> String {
        var code = ""
        var last: Character?
        for point in points {
            for (id, rect) in keyFrames where id.hasPrefix("char-") && rect.contains(point) {
                if let letter = id.dropFirst(5).first, letter != last {
                    code.append(letter)
                    last = letter
                }
                break
            }
        }
        return code
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

private struct GlideTrailOverlay: View {
    let points: [CGPoint]

    var body: some View {
        Canvas { context, _ in
            guard points.count > 1 else { return }
            var path = Path()
            path.addLines(points)
            context.stroke(
                path,
                with: .color(Color.accentColor.opacity(0.7)),
                style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

private struct KeyRow: View {
    let keys: [KeySpec]
    @ObservedObject var model: KeyboardModel

    private var rowHeight: CGFloat {
        keys.first?.isCompact == true ? 36 : 44
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 5) {
                ForEach(keys) { key in
                    if key.isSpacer {
                        Color.clear
                            .frame(width: width(for: key, totalWidth: geometry.size.width))
                    } else {
                        KeyButton(
                            key: key,
                            onTap: { model.tap(key.action) },
                            onSwipeUp: key.swipeUp.map { action -> () -> Void in
                                { model.tap(action) }
                            },
                            onSwipeDown: key.swipeDown.map { action -> () -> Void in
                                { model.tap(action) }
                            },
                            onSpaceDrag: key.isSpace ? { (steps: Int) in model.moveCursorBy(steps) } : nil,
                            onRepeatBegin: key.action == .delete ? { model.beginDeleteRepeat() } : nil,
                            onRepeatEnd: key.action == .delete ? { model.endDeleteRepeat() } : nil
                        )
                        .frame(width: width(for: key, totalWidth: geometry.size.width))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: rowHeight)
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

/// 键帽：点按 / 上下滑（数字、清空、撤回）/ 空格横滑移动光标 / 删除长按连删。
private struct KeyButton: View {
    let key: KeySpec
    let onTap: () -> Void
    let onSwipeUp: (() -> Void)?
    let onSwipeDown: (() -> Void)?
    let onSpaceDrag: ((Int) -> Void)?
    let onRepeatBegin: (() -> Void)?
    let onRepeatEnd: (() -> Void)?

    @State private var pressed = false
    @State private var spaceDragAccum: CGFloat = 0
    @State private var lastDragX: CGFloat = 0
    @State private var pressStart: Date?

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
        .scaleEffect(pressed ? 0.94 : 1)
        .animation(.easeOut(duration: 0.08), value: pressed)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !pressed {
                        pressed = true
                        pressStart = Date()
                        onRepeatBegin?()
                    }
                    if let onSpaceDrag {
                        handleSpaceDrag(value.translation.width, emit: onSpaceDrag)
                    }
                }
                .onEnded { value in
                    pressed = false
                    spaceDragAccum = 0
                    lastDragX = 0
                    let held = Date().timeIntervalSince(pressStart ?? Date())
                    pressStart = nil
                    onRepeatEnd?()

                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) < 16, abs(dy) < 16 {
                        // 长按已触发连删时不再补一次。
                        if onRepeatBegin != nil, held >= 0.4 { return }
                        onTap()
                    } else if dy < -14, abs(dx) < 40, let onSwipeUp {
                        onSwipeUp()
                    } else if dy > 14, abs(dx) < 40, let onSwipeDown {
                        onSwipeDown()
                    }
                }
        )
    }

    private func handleSpaceDrag(_ translation: CGFloat, emit: (Int) -> Void) {
        spaceDragAccum += translation - lastDragX
        lastDragX = translation
        let stepWidth: CGFloat = 12
        while abs(spaceDragAccum) >= stepWidth {
            let step = spaceDragAccum > 0 ? 1 : -1
            emit(step)
            spaceDragAccum -= CGFloat(step) * stepWidth
        }
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
