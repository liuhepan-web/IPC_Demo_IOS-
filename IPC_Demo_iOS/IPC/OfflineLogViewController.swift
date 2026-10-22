import UIKit
import ThingSmartHomeKit

/// 离线日志（对应 Android OfflineLogActivity）：上传 SDK 日志用于排查问题。
final class OfflineLogViewController: UIViewController {

    private let logPathLabel = UILabel()
    private let uploadBtn = UIButton(type: .system)
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "离线日志"
        view.backgroundColor = .white
        setupUI()

        // ThingSmartSDK 会把日志写到沙盒 Cache 目录
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        logPathLabel.text = (cache?.path ?? "未知") + "/com.tuya.smart/log"
    }

    private func setupUI() {
        logPathLabel.numberOfLines = 0; logPathLabel.font = .systemFont(ofSize: 13)
        logPathLabel.textColor = .darkGray; logPathLabel.textAlignment = .center

        uploadBtn.setTitle("导出日志信息", for: .normal)
        uploadBtn.applyPrimary()
        uploadBtn.addTarget(self, action: #selector(onUpload), for: .touchUpInside)

        statusLabel.text = "点击上传 SDK 运行日志（用于问题排查）"
        statusLabel.textColor = .gray; statusLabel.textAlignment = .center; statusLabel.font = .systemFont(ofSize: 13)

        let stack = UIStackView(arrangedSubviews: [logPathLabel, statusLabel, uploadBtn])
        stack.axis = .vertical; stack.spacing = 20
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 40, left: 32, bottom: 40, right: 32)
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    @objc private func onUpload() {
        // 5.0 SDK 未提供日志上传 API，改为导出本地日志文件用于排查
        let logDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.tuya.smart/log", isDirectory: true)
        var content = "Tuya SDK 日志目录: \(logDir?.path ?? "未知")\n\n"
        if let dir = logDir, let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            content += "日志文件: \(files.joined(separator: ", "))\n"
        } else {
            content += "（日志目录为空或尚未产生日志）\n"
        }
        let vc = UIActivityViewController(activityItems: [content], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = view
        present(vc, animated: true)
        statusLabel.text = "已导出日志信息，请选择分享方式"
    }
}
