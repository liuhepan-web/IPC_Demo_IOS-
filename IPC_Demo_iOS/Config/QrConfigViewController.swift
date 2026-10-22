import UIKit
import CoreImage
import ThingSmartHomeKit
import ThingSmartActivatorKit

/// 摄像头二维码配网（对应 Android DeviceConfigQrActivity）。
/// App 生成含 Wi-Fi 凭证 + Token 的二维码 → 摄像机扫码 → 配网成功。
///
/// 说明：涂鸦 5.0 SDK 移除了旧版 `ThingSmartCameraActivator`（无对应新类），
/// 本页采用与官方等价的通用流程：
///   1. `ThingSmartHomeKitActivator.getToken(withHomeID:)` 获取配网 Token；
///   2. 生成二维码内容 `{"s": ssid, "p": pwd, "t": token}`（与官方扫码格式一致）；
///   3. 轮询家庭设备列表，发现新设备即视为配网成功。
final class QrConfigViewController: UIViewController {

    private let ssidField = UITextField()
    private let passwordField = UITextField()
    private let startButton = UIButton(type: .system)
    private let qrImageView = UIImageView()
    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)

    private var token: String?
    private var pollTimer: Timer?
    private var knownDeviceIds: Set<String> = []
    private var hasSucceeded = false

    private enum PairState { case idle, fetching, waiting, success, failed }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "摄像头二维码配网"
        view.backgroundColor = UIColor(hex: TuyaConfig.bgGray)
        setupUI()
        snapshotKnownDevices()
    }

    deinit { pollTimer?.invalidate() }

    private func setupUI() {
        // 点击空白处收起键盘
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        ssidField.placeholder = "Wi-Fi 名称(SSID)"; ssidField.borderStyle = .roundedRect; ssidField.backgroundColor = .white
        passwordField.placeholder = "Wi-Fi 密码"; passwordField.borderStyle = .roundedRect; passwordField.backgroundColor = .white; passwordField.isSecureTextEntry = true
        [ssidField, passwordField].forEach { $0.heightAnchor.constraint(equalToConstant: 44).isActive = true }
        startButton.setTitle("生成二维码", for: .normal); startButton.applyPrimary()
        startButton.addTarget(self, action: #selector(onStart), for: .touchUpInside)
        spinner.hidesWhenStopped = true

        qrImageView.contentMode = .scaleAspectFit
        qrImageView.backgroundColor = .white
        qrImageView.layer.cornerRadius = 8
        qrImageView.heightAnchor.constraint(equalTo: qrImageView.widthAnchor).isActive = true

        statusLabel.text = "填写 2.4G Wi-Fi 后生成二维码，正对摄像机扫描（约 15-20cm）"
        statusLabel.font = .systemFont(ofSize: 13); statusLabel.textColor = .gray; statusLabel.numberOfLines = 0

        let card = UIStackView(arrangedSubviews: [ssidField, passwordField, startButton, qrImageView, statusLabel, spinner])
        card.axis = .vertical; card.spacing = 14
        card.isLayoutMarginsRelativeArrangement = true
        card.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24)
        card.backgroundColor = .white; card.layer.cornerRadius = 12
        let container = UIStackView(arrangedSubviews: [card])
        container.isLayoutMarginsRelativeArrangement = true
        container.layoutMargins = UIEdgeInsets(top: 24, left: 24, bottom: 40, right: 24)
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
        let password = passwordField.text ?? ""

        applyState(.fetching, "正在获取配网 Token...")
        ThingSmartHomeKitActivator().getTokenWithHomeID(homeId, success: { [weak self] (token: String?) in
            guard let self = self else { return }
            guard let token = token, !token.isEmpty else {
                self.applyState(.failed, "获取 Token 失败：Token 为空")
                return
            }
            self.token = token
            self.showQRCode(ssid: ssid, password: password, token: token)
        }, failure: { [weak self] (error: Error?) in
            DispatchQueue.main.async { self?.applyState(.failed, "获取 Token 失败：\(error?.localizedDescription ?? "")") }
        })
    }

    // MARK: - 二维码生成 + 设备轮询
    private func showQRCode(ssid: String, password: String, token: String) {
        let payload: String
        if let data = try? JSONSerialization.data(withJSONObject: ["s": ssid, "p": password, "t": token],
                                                  options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            payload = s
        } else {
            payload = "{\"s\":\"\(ssid)\",\"p\":\"\(password)\",\"t\":\"\(token)\"}"
        }

        guard let qr = Self.qrImage(for: payload) else {
            applyState(.failed, "二维码生成失败")
            return
        }
        qrImageView.image = qr
        // 生成二维码后立即收起键盘，避免遮挡
        view.endEditing(true)
        applyState(.waiting, "请使用摄像机扫描二维码（等待设备上线，约 1-2 分钟）")
        startPolling()
    }

    private static func qrImage(for content: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(content.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        return UIImage(ciImage: scaled)
    }

    /// 记录当前家庭已有的设备，作为“新设备”的比对基线
    private func snapshotKnownDevices() {
        let homeId = SessionManager.currentHome()
        guard homeId != 0 else { return }
        let home = ThingSmartHome(homeId: homeId)
        home?.getDataWithSuccess({ (model: ThingSmartHomeModel?) in
            let ids = (home?.deviceList ?? []).compactMap { $0.devId as String? }
            DispatchQueue.main.async { self.knownDeviceIds = Set(ids) }
        }, failure: nil)
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.pollForNewDevice()
        }
    }

    private func pollForNewDevice() {
        guard !hasSucceeded else { pollTimer?.invalidate(); return }
        let homeId = SessionManager.currentHome()
        guard homeId != 0 else { return }
        let home = ThingSmartHome(homeId: homeId)
        home?.getDataWithSuccess({ [weak self] (model: ThingSmartHomeModel?) in
            DispatchQueue.main.async {
                guard let self = self, !self.hasSucceeded else { return }
                let newDevice = (home?.deviceList ?? []).first { !self.knownDeviceIds.contains($0.devId) }
                if let device = newDevice {
                    self.hasSucceeded = true
                    self.pollTimer?.invalidate()
                    self.onSuccess(device)
                }
            }
        }, failure: nil)
    }

    private func applyState(_ state: PairState, _ text: String) {
        statusLabel.text = text
        switch state {
        case .idle: spinner.stopAnimating(); startButton.isEnabled = true
        case .fetching, .waiting: spinner.startAnimating(); startButton.isEnabled = false
        case .success: spinner.stopAnimating(); startButton.isEnabled = true; startButton.setTitle("前往设备列表", for: .normal)
        case .failed: spinner.stopAnimating(); startButton.isEnabled = true
        }
    }

    private func onSuccess(_ device: ThingSmartDeviceModel) {
        applyState(.success, "配网成功：\(device.name)")
        showToast("配网成功")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.navigationController?.pushViewController(DeviceListViewController(), animated: true)
        }
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
}
