import UIKit
import ThingSmartHomeKit

/// 门铃面板（对应 Android CameraDoorBellActivity）：开启来电监听，并演示手动视频通话。
final class CameraDoorBellViewController: UIViewController {

    private let devId: String
    private let tipLabel = UILabel()
    private let monitorBtn = UIButton(type: .system)
    private let callBtn = UIButton(type: .system)

    init(devId: String) {
        self.devId = devId
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "门铃"
        view.backgroundColor = .white
        setupUI()
    }

    private func setupUI() {
        tipLabel.numberOfLines = 0
        tipLabel.text = "开启监听后，设备上报门铃来电 DP 时会自动弹出接听界面；\n接听即通过对讲通道建立视频通话。"
        tipLabel.textAlignment = .center; tipLabel.textColor = .gray; tipLabel.font = .systemFont(ofSize: 14)

        monitorBtn.setTitle("开启来电监听", for: .normal)
        monitorBtn.applyPrimary()
        monitorBtn.addTarget(self, action: #selector(onMonitor), for: .touchUpInside)

        callBtn.setTitle("发起视频通话", for: .normal)
        callBtn.applySecondary()
        callBtn.addTarget(self, action: #selector(onCall), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [tipLabel, monitorBtn, callBtn])
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

    @objc private func onMonitor() {
        DoorbellCallManager.shared.observe(devId: devId)
        showToast("已开启来电监听")
    }

    @objc private func onCall() {
        let panel = CameraPanelViewController(devId: devId)
        navigationController?.pushViewController(panel, animated: true)
    }
}
