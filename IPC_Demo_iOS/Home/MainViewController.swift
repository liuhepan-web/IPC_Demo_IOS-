import UIKit
import ThingSmartHomeKit

/// 主控台（对应 Android MainActivity）：家庭管理 + 配网入口 + 设备列表 + 离线日志 + 退出。
final class MainViewController: UIViewController {

    private let currentHomeLabel = UILabel()
    private let statusLabel = UILabel()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "IPC Demo"
        view.backgroundColor = UIColor(hex: TuyaConfig.bgGray)
        setupUI()
        navigationItem.hidesBackButton = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshCurrentHome()
        queryHomeList()
    }

    private func setupUI() {
        currentHomeLabel.font = .systemFont(ofSize: 16, weight: .medium)
        currentHomeLabel.textColor = UIColor(hex: TuyaConfig.brandDark)
        currentHomeLabel.numberOfLines = 0
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .gray
        statusLabel.numberOfLines = 0

        let homeCard = card(views: [currentHomeLabel, statusLabel])

        stack.axis = .vertical
        stack.spacing = 12
        stack.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.isLayoutMarginsRelativeArrangement = true

        let actionCard = card(views: [
            actionButton("创建家庭", #selector(onCreateHome)),
            actionButton("家庭列表", #selector(onHomeList)),
            actionButton("刷新家庭列表", #selector(onRefreshHomes)),
            actionButton("EZ 配网", #selector(onEz)),
            actionButton("AP 配网", #selector(onAp)),
            actionButton("摄像头二维码配网", #selector(onQr)),
            actionButton("设备列表", #selector(onDeviceList)),
            actionButton("离线日志", #selector(onOfflineLog)),
            actionButton("退出登录", #selector(onLogout), danger: true)
        ])

        let content = UIStackView(arrangedSubviews: [homeCard, stack, actionCard])
        content.axis = .vertical
        content.spacing = 16
        content.isLayoutMarginsRelativeArrangement = true
        content.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)

        scrollView.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func card(views: [UIView]) -> UIView {
        let v = UIStackView(arrangedSubviews: views)
        v.axis = .vertical; v.spacing = 8
        v.isLayoutMarginsRelativeArrangement = true
        v.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        v.backgroundColor = .white; v.layer.cornerRadius = 12
        return v
    }

    private func actionButton(_ title: String, _ action: Selector, danger: Bool = false) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        if danger {
            b.setTitleColor(.systemRed, for: .normal)
        } else {
            b.setTitleColor(.white, for: .normal)
            b.backgroundColor = UIColor(hex: TuyaConfig.brandMain)
        }
        b.layer.cornerRadius = 8
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        b.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    // MARK: - Actions
    @objc private func onCreateHome() {
        navigationController?.pushViewController(CreateHomeViewController(), animated: true)
    }
    @objc private func onHomeList() {
        navigationController?.pushViewController(HomeListViewController(), animated: true)
    }
    @objc private func onRefreshHomes() { queryHomeList() }
    @objc private func onEz() {
        guard ensureHome() else { return }
        navigationController?.pushViewController(EzConfigViewController(), animated: true)
    }
    @objc private func onAp() {
        guard ensureHome() else { return }
        navigationController?.pushViewController(ApConfigViewController(), animated: true)
    }
    @objc private func onQr() {
        guard ensureHome() else { return }
        navigationController?.pushViewController(QrConfigViewController(), animated: true)
    }
    @objc private func onDeviceList() {
        guard ensureHome() else { return }
        navigationController?.pushViewController(DeviceListViewController(), animated: true)
    }
    @objc private func onOfflineLog() {
        navigationController?.pushViewController(OfflineLogViewController(), animated: true)
    }
    @objc private func onLogout() {
        (UIApplication.shared.delegate as? AppDelegate)?.logoutAndRoute()
    }

    private func ensureHome() -> Bool {
        if SessionManager.currentHome() != 0 { return true }
        showToast("请先创建或选择家庭")
        return false
    }

    // MARK: - Home queries
    private func refreshCurrentHome() {
        let homeId = SessionManager.currentHome()
        guard homeId != 0 else { currentHomeLabel.text = "当前家庭：未选择"; return }
        ThingSmartHome(homeId: homeId)?.getDataWithSuccess { [weak self] (model: ThingSmartHomeModel?) in
            DispatchQueue.main.async { self?.currentHomeLabel.text = "当前家庭：\(model?.name ?? "未知") (\(homeId))" }
        } failure: { [weak self] (error: Error?) in
            DispatchQueue.main.async { self?.currentHomeLabel.text = "当前家庭：ID \(homeId)" }
        }
    }

    private func queryHomeList() {
        ThingSmartHomeManager().getHomeList { [weak self] (homes: [ThingSmartHomeModel]?) in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let homes = homes, !homes.isEmpty {
                    let text = homes.map { "\($0.name) (\($0.homeId))" }.joined(separator: "\n")
                    self.statusLabel.text = text
                    if SessionManager.currentHome() == 0 {
                        SessionManager.setCurrentHome(homes[0].homeId)
                        self.refreshCurrentHome()
                    }
                } else {
                    self.statusLabel.text = "暂无家庭，请先创建"
                }
            }
        } failure: { [weak self] (error: Error?) in
            DispatchQueue.main.async { self?.showError(code: nil, message: error?.localizedDescription) }
        }
    }
}
