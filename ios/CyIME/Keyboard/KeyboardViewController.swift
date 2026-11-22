import SwiftUI
import UIKit

final class KeyboardViewController: UIInputViewController {
    private var model: KeyboardModel?
    private var hostingController: UIHostingController<KeyboardRootView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        AppGroup.prepare()
        AppGroup.appendLog("Keyboard extension viewDidLoad")

        let rimeReady = RimeEngine.shared.setup(
            sharedDataDir: AppGroup.rimeSharedURL.path,
            userDataDir: AppGroup.rimeUserURL.path
        )
        AppGroup.appendLog("RimeEngine setup ready=\(rimeReady)")

        view.backgroundColor = .clear

        let model = KeyboardModel(
            insertText: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            },
            deleteBackward: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            },
            advanceInputMode: { [weak self] in
                self?.advanceToNextInputMode()
            },
            dismissKeyboard: { [weak self] in
                self?.dismissKeyboard()
            },
            moveCursor: { [weak self] steps in
                self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: steps)
            }
        )
        self.model = model

        let hosting = UIHostingController(rootView: KeyboardRootView(model: model))
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear
        hosting.view.isOpaque = false

        addChild(hosting)
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
        hostingController = hosting

        // 候选栏 46 + 4 行 × 44 + 行间距 ≈ 246
        let height = view.heightAnchor.constraint(equalToConstant: 246)
        height.priority = UILayoutPriority(999)
        height.isActive = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 主 App 可能刚完成数据部署：未就绪时自动重试并刷新状态。
        _ = RimeEngine.shared.ensureReady()
        model?.refreshEngineStatus()
        model?.updateContext(hasText: textDocumentProxy.hasText)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model?.updateContext(hasText: textDocumentProxy.hasText)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        AppGroup.appendLog("Keyboard extension viewDidDisappear")
    }
}
