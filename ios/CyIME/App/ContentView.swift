import SwiftUI
import UIKit

@MainActor
struct ContentView: View {
    @State private var testText = ""
    @State private var logText = ""
    @State private var groupStatus = "检查中"
    @State private var probeText = ""
    @State private var rimeStatus = "未准备"
    @State private var isPreparing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    setupCard
                    rimeCard
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
                prepareRimeIfNeeded()
            }
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("M1 · Rime 引擎")
                .font(.headline)

            Text("首次使用需在本页完成 Rime 数据安装与部署；完成后键盘即可输入中文。")
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

    private var rimeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rime 数据")
                .font(.headline)

            Text(rimeStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                Button(isPreparing ? "部署中…" : "安装数据并部署") {
                    prepareRime()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPreparing)

                if isPreparing {
                    ProgressView()
                }
            }

            Text("数据：简体全拼 pinyin_simp。部署成功后回到键盘重新切换一次即可生效。")
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

            if !probeText.isEmpty {
                Text(probeText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

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

    private func prepareRimeIfNeeded() {
        if RimeEngine.shared.isReady {
            rimeStatus = "就绪 · pinyin_simp 已加载"
            return
        }
        prepareRime()
    }

    /// 安装数据并部署。部署是阻塞的原生调用，一次性操作，期间显示“部署中…”。
    private func prepareRime() {
        guard !isPreparing else { return }
        isPreparing = true
        let install = RimeDataInstaller.installIfNeeded()
        rimeStatus = "\(install.message)，部署中…"
        AppGroup.appendLog("Rime install: \(install.message)")

        Task { @MainActor in
            await Task.yield()   // 先让“部署中…”渲染出来
            let shared = AppGroup.rimeSharedURL.path
            let user = AppGroup.rimeUserURL.path
            let engine = RimeEngine.shared
            let setupOK = engine.setup(sharedDataDir: shared, userDataDir: user)
            let deployed = setupOK ? engine.deploy() : false
            isPreparing = false

            if deployed && engine.isReady {
                rimeStatus = "就绪 · pinyin_simp 已加载"
            } else if setupOK {
                rimeStatus = "部署未完成（详见下方诊断日志）"
            } else {
                rimeStatus = "初始化失败（详见下方诊断日志）"
            }
            AppGroup.appendLog(
                "Rime prepare install=\(install.installed) setup=\(setupOK) deployed=\(deployed) ready=\(engine.isReady)"
            )
            refresh()
        }
    }

    private func refresh() {
        if let id = AppGroup.resolvedIdentifier {
            groupStatus = "可用 · \(id)\n路径：\(AppGroup.rootURL.path)"
        } else {
            groupStatus = "不可用（签名未注入 App Group 权限，5 个已授权群组均探测失败）"
        }
        probeText = AppGroup.probeResults
            .map { "\($0.1 ? "✓" : "✗") \($0.0)" }
            .joined(separator: "\n")
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
