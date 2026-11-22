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
                        KeyButton(key: key) {
                            model.tap(key.action)
                        }
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

private struct KeyButton: View {
    let key: KeySpec
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(key.label)
                .font(.system(size: fontSize, weight: key.isSpecial ? .medium : .regular))
                .foregroundStyle(key.isAccent ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    fill,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private var fontSize: CGFloat {
        switch key.action {
        case .space:
            return 15
        case .globe:
            return 18
        default:
            return key.isSpecial ? 14 : 20
        }
    }

    private var fill: Color {
        if key.isAccent {
            return .accentColor.opacity(0.9)
        }
        if key.isSpecial {
            return Color(uiColor: .tertiarySystemFill)
        }
        return Color(uiColor: .secondarySystemBackground).opacity(0.92)
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
                        .background(
                            Color(uiColor: .tertiarySystemFill),
                            in: Capsule()
                        )
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
