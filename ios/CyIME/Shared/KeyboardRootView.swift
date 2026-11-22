import SwiftUI
import UIKit

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            CandidateBar(model: model)

            ForEach(Array(model.rows.enumerated()), id: \.offset) { item in
                KeyRow(keys: item.element, model: model)
            }
        }
        .padding(.vertical, 4)
        .background(keyboardBackground)
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
    @ObservedObject var model: KeyboardModel

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
                            onSpaceDrag: key.isSpace ? { (steps: Int) in model.moveCursorBy(steps) } : nil
                        )
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

/// 键帽：点按 / 上滑（出数字或符号）/ 空格横向拖动移动光标。
private struct KeyButton: View {
    let key: KeySpec
    let onTap: () -> Void
    let onSwipeUp: (() -> Void)?
    let onSpaceDrag: ((Int) -> Void)?

    @State private var pressed = false
    @State private var spaceDragAccum: CGFloat = 0
    @State private var lastDragX: CGFloat = 0

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
        .shadow(color: .black.opacity(0.07), radius: 1, x: 0, y: 1)
        .scaleEffect(pressed ? 0.94 : 1)
        .animation(.easeOut(duration: 0.08), value: pressed)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !pressed { pressed = true }
                    if let onSpaceDrag {
                        handleSpaceDrag(value.translation.width, emit: onSpaceDrag)
                    }
                }
                .onEnded { value in
                    pressed = false
                    spaceDragAccum = 0
                    let dx = value.translation.width
                    let dy = value.translation.height
                    if abs(dx) < 16, abs(dy) < 16 {
                        onTap()
                    } else if dy < -14, abs(dx) < 40, let onSwipeUp {
                        onSwipeUp()
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
        default: return key.isSpecial ? 14 : 20
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
