import UIKit
import ThingSmartHomeKit
import ThingSmartActivatorKit
import ThingSmartActivatorCoreKit

/// AP（热点）配网（对应 Android DeviceConfigApActivity）。
/// 流程：取 token → 跳转系统 Wi-Fi 设置连接设备热点 → 返回后启动 AP 配网。
final class ApConfigViewController: UIViewController {

    private let ssidField = UITextField()
    private let passwordField = UITextField()
    private let startButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let activator = ThingSmartActivator()

    private var homeId: Int64 = 0
    private var ssid: String = ""
    private var password: String = ""
    private var token: String = ""
    private var waitingWifiReturn = false
    private var activating = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "AP 配网"
        view.backgroundColor = UIColor(hex: TuyaConfig.bgGray)
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if waitingWifiReturn, !token.isEmpty, !activating {
            waitingWifiReturn = false
            startApActivator()
        }
    }

    private func setupUI() {
        ssidField.placeholder = "路由 Wi-Fi 名称(SSID)"; ssidField.borderStyle = .roundedRect; ssidField.backgroundColor = .white
        passwordField.placeholder = "路由 Wi-Fi 密码"; passwordField.borderStyle = .roundedRect; passwordField.backgroundColor = .white; passwordField.isSecureTextEntry = true
        [ssidField, passwordField].forEach { $0.heightAnchor.constraint(equalToConstant: 44).isActive = true }
        startButton.setTitle("开始配网", for: .normal); startButton.applyPrimary()
        startButton.addTarget(self, action: #selector(onStart), for: .touchUpInside)
        spinner.hidesWhenStopped = true

        let tip = UILabel()
        tip.text = "步骤：1)点开始 → 2)跳转 Wi-Fi 设置连接设备热点(SmartLife-XXXX) → 3)返回本页自动配网"
        tip.font = .systemFont(ofSize: 12); tip.textColor = .gray; tip.numberOfLines = 0

        let card = UIStackView(arrangedSubviews: [tip, ssidField, passwordField, startButton, spinner])
        card.axis = .vertical; card.spacing = 14
        card.isLayoutMarginsRelativeArrangement = true
        card.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24)
        card.backgroundColor = .white; card.layer.cornerRadius = 12
        let container = UIStackView(arrangedSubviews: [card])
        container.isLayoutMarginsRelativeArrangement = true
        container.layoutMargins = UIEdgeInsets(top: 40, left: 24, bottom: 40, right: 24)
        view.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    @objc private func onStart() {
        guard let ssid = ssidField.text?.trimmingCharacters(in: .whitespaces), !ssid.isEmpty else {
            showToast("请输入 Wi-Fi 名称"); return
        }
        let homeId = SessionManager.currentHome()
        guard homeId != 0 else { showToast("请先选择家庭"); return }
        self.homeId = homeId
        self.ssid = ssid
        self.password = passwordField.text ?? ""

        setLoading(true)
        activator.delegate = self
        ThingSmartHomeKitActivator().getTokenWithHomeID(homeId, success: { [weak self] (token: String?) in
            guard let self = self else { return }
            guard let token = token, !token.isEmpty else {
                self.setLoading(false); self.showError(code: nil, message: "获取 Token 失败：Token 为空")
                return
            }
            self.token = token
            self.waitingWifiReturn = true
            self.setLoading(false)
            self.showToast("请连接设备热点")
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }, failure: { [weak self] (error: Error?) in
            DispatchQueue.main.async { self?.setLoading(false); self?.showError(code: nil, message: error?.localizedDescription) }
        })
    }

    private func startApActivator() {
        activating = true
        setLoading(true)
        activator.startConfigWiFi(.AP, ssid: ssid, password: password, token: token, regInfo: nil, timeout: 100)
    }

    private func setLoading(_ loading: Bool) {
        startButton.isEnabled = !loading
        loading ? spinner.startAnimating() : spinner.stopAnimating()
    }

    private func onActivated(_ device: ThingSmartDeviceModel?) {
        activating = false; setLoading(false)
        activator.stopConfigWiFi()
        showToast("配网成功")
        navigationController?.pushViewController(DeviceListViewController(), animated: true)
    }
}

extension ApConfigViewController: ThingSmartActivatorDelegate {
    func activator(_ activator: ThingSmartActivator, didReceiveDevice deviceModel: ThingSmartDeviceModel?, error: (any Error)?) {
        DispatchQueue.main.async { [weak self] in
            if let deviceModel = deviceModel { self?.onActivated(deviceModel) }
            else { self?.activating = false; self?.setLoading(false); self?.showError(code: nil, message: error?.localizedDescription) }
        }
    }
}
