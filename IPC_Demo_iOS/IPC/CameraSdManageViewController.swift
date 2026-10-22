import UIKit
import ThingSmartHomeKit

/// SD 卡管理（对应 Android CameraSdManageActivity）：查看存储卡状态 / 容量，格式化存储卡。
final class CameraSdManageViewController: UIViewController {

    private let devId: String
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    private var rows: [(String, String)] = []

    init(devId: String) {
        self.devId = devId
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "SD 卡管理"
        view.backgroundColor = .white
        setupUI()
        refresh()
    }

    private func setupUI() {
        statusLabel.text = "读取中…"; statusLabel.textColor = .gray; statusLabel.textAlignment = .center
        view.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        tableView.dataSource = self; tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "sd")
        tableView.tableFooterView = footerView()
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func footerView() -> UIView {
        let v = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 80))
        let btn = UIButton(type: .system)
        btn.setTitle("格式化存储卡", for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = .systemRed
        btn.layer.cornerRadius = 8
        btn.addTarget(self, action: #selector(onFormat), for: .touchUpInside)
        v.addSubview(btn)
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: v.topAnchor, constant: 16),
            btn.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 24),
            btn.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -24),
            btn.heightAnchor.constraint(equalToConstant: 44)
        ])
        return v
    }

    // MARK: - 读取 DP
    private func refresh() {
        guard let device = ThingSmartDevice(deviceId: devId) else {
            statusLabel.text = "设备不存在"; return
        }
        let dps = device.deviceModel.dps
        let sdStatus = (dps?[DP.sdStatus.rawValue] as? Int) ?? 0   // 0 无卡 / 1 异常 / 2 正常
        let storage = (dps?[DP.sdStorage.rawValue] as? Int) ?? 0    // 总容量 MB
        let statusText: String
        switch sdStatus {
        case 2: statusText = "正常"
        case 1: statusText = "异常"
        default: statusText = "未插卡"
        }
        rows = [
            ("存储卡状态", statusText),
            ("总容量", "\(storage) MB"),
            ("设备 ID", devId)
        ]
        statusLabel.text = sdStatus == 2 ? "存储卡已就绪" : "请检查存储卡"
        tableView.reloadData()
    }

    @objc private func onFormat() {
        confirm(title: "格式化存储卡", message: "将清除卡内全部录像，确定继续？") { [weak self] in
            guard let self = self else { return }
            ThingSmartDevice(deviceId: self.devId)?
                .publishDps([DP.sdFormat.rawValue: 1], success: {
                    DispatchQueue.main.async { self.showToast("已发送格式化指令") }
                }, failure: { error in
                    DispatchQueue.main.async { self.showError(code: nil, message: error?.localizedDescription) }
                })
        }
    }
}

extension CameraSdManageViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "sd", for: indexPath)
        let (k, v) = rows[indexPath.row]
        cell.textLabel?.text = k
        cell.detailTextLabel?.text = v
        cell.selectionStyle = .none
        return cell
    }
}
