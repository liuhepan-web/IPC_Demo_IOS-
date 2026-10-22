import UIKit
import ThingSmartHomeKit
import ThingSmartActivatorKit
import ThingSmartActivatorCoreKit

/// EZ（智能配网）配网（对应 Android DeviceConfigEzActivity）。
final class EzConfigViewController: UIViewController {

    private let ssidField = UITextField()
    private let passwordField = UITextField()
    private let startButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var activating = false
    private let activator = ThingSmartActivator()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "EZ 配网"
        view.backgroundColor = UIColor(hex: TuyaConfig.bgGray)
        ssidField.text = UIDevice.current.name   // 默认填充本机名作为提示（真实需读 Wi-Fi SSID，需 NEHotspotHelper 权限）
        setupUI()
    }

    private func setupUI() {
        ssidField.placeholder = "Wi-Fi 名称(SSID)"; ssidField.borderStyle = .roundedRect; ssidField.backgroundColor = .white
        passwordField.placeholder = "Wi-Fi 密码"; passwordField.borderStyle = .roundedRect; passwordField.backgroundColor = .white; passwordField.isSecureTextEntry = true
        [ssidField, passwordField].forEach { $0.heightAnchor.constraint(equalToConstant: 44).isActive = true }
        startButton.setTitle("开始配网", for: .normal); startButton.applyPrimary()
        startButton.addTarget(self, action: #selector(onStart), for: .touchUpInside)
        spinner.hidesWhenStopped = true

        let card = UIStackView(arrangedSubviews: [ssidField, passwordField, startButton, spinner])
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
        let password = passwordField.text ?? ""
        let homeId = SessionManager.currentHome()
        guard homeId != 0 else { showToast("请先选择家庭"); return }

        setLoading(true)
        activator.delegate = self
        ThingSmartHomeKitActivator().getTokenWithHomeID(homeId, success: { [weak self] (token: String?) in
            guard let self = self else { return }
            guard let token = token, !token.isEmpty else {
                self.setLoading(false); self.showError(code: nil, message: "获取 Token 失败：Token 为空")
                return
            }
            self.activator.startConfigWiFi(.EZ, ssid: ssid, password: password, token: token, regInfo: nil, timeout: 100)
        }, failure: { [weak self] (error: Error?) in
            DispatchQueue.main.async { self?.setLoading(false); self?.showError(code: nil, message: error?.localizedDescription) }
        })
    }

    private func setLoading(_ loading: Bool) {
        activating = loading
        startButton.isEnabled = !loading
        loading ? spinner.startAnimating() : spinner.stopAnimating()
    }

    private func onActivated(_ device: ThingSmartDeviceModel?) {
        setLoading(false)
        activator.stopConfigWiFi()
        showToast("配网成功")
        navigationController?.pushViewController(DeviceListViewController(), animated: true)
    }
}

extension EzConfigViewController: ThingSmartActivatorDelegate {
    func activator(_ activator: ThingSmartActivator, didReceiveDevice deviceModel: ThingSmartDeviceModel?, error: (any Error)?) {
        DispatchQueue.main.async { [weak self] in
            if let deviceModel = deviceModel {
                self?.onActivated(deviceModel)
            } else {
                self?.setLoading(false)
                self?.showError(code: nil, message: error?.localizedDescription)
            }
        }
    }
}
