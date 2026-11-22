import SwiftUI
import UIKit

struct ContentView: View {
    @State private var testText = ""
    @State private var logText = ""
    @State private var groupStatus = "检查中"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    setupCard
                    testCard
                    diagnosticsCard
                }
                .padding()
            }
            .navigationTitle("CyIME")
            .background(Color(uiColor: .systemGroupedBackground))
            .onAppear {
                AppGroup.prepare()
                AppGroup.appendLog("App launched")
                refresh()
            }
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("M0 · 最小键盘")
                .font(.headline)

            Text("当前只验证键盘扩展、上屏和 App Group。Rime 引擎下一步接入。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("打开设置") {
                openSettings()
            }
            .buttonStyle(.borderedProminent)

            Button("打开键盘设置") {
                openKeyboardSettings()
            }
            .buttonStyle(.bordered)

            Text("设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → CyIME，然后打开“允许完全访问”。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("试打")
                .font(.headline)

            TextEditor(text: $testText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(8)
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            Text("把系统键盘切换成 CyIME 后在这里试打。中英切换、候选、数字、删除、空格、回车应可用。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("诊断")
                    .font(.headline)
                Spacer()
                Button("刷新") {
                    refresh()
                }
                .font(.footnote)
            }

            Text("App Group：\(groupStatus)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            ScrollView {
                Text(logText.isEmpty ? "暂无日志" : logText)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 180)
            .padding(8)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )

            Button("复制 App Group 路径") {
                UIPasteboard.general.string = AppGroup.rootURL.path
            }
            .font(.footnote)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func refresh() {
        groupStatus = AppGroup.containerURL == nil
            ? "不可用（检查签名 / entitlement）"
            : AppGroup.rootURL.path
        logText = AppGroup.tailLog(maxLines: 100)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func openKeyboardSettings() {
        guard let url = URL(string: "prefs:root=General&path=Keyboard") else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    ContentView()
}
