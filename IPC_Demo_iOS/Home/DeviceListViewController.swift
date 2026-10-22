import UIKit
import ThingSmartHomeKit

/// 设备列表（对应 Android DeviceListActivity）：展示当前家庭设备，点击进入预览，长按移除。
final class DeviceListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private var devices: [ThingSmartDeviceModel] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设备列表"
        view.backgroundColor = .white
        tableView.dataSource = self; tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        emptyLabel.text = "暂无设备"; emptyLabel.textColor = .gray; emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadDevices()
    }

    private func loadDevices() {
        let homeId = SessionManager.currentHome()
        guard homeId != 0 else {
            devices = []; tableView.reloadData(); emptyLabel.isHidden = false
            emptyLabel.text = "请先选择家庭"
            return
        }
        let home = ThingSmartHome(homeId: homeId)
        home?.getDataWithSuccess { [weak self] (model: ThingSmartHomeModel?) in
            DispatchQueue.main.async {
                self?.devices = home?.deviceList ?? []
                self?.tableView.reloadData()
                self?.emptyLabel.isHidden = !(self?.devices.isEmpty ?? true)
            }
        } failure: { [weak self] (error: Error?) in
            DispatchQueue.main.async { self?.showError(code: nil, message: error?.localizedDescription) }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { devices.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let dev = devices[indexPath.row]
        let online = dev.isOnline ? "在线" : "离线"
        cell.textLabel?.text = dev.name
        cell.detailTextLabel?.text = "\(DeviceCapability.typeLabel(dev.devId)) · \(online) · \(dev.devId)"
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let dev = devices[indexPath.row]
        tableView.deselectRow(at: indexPath, animated: true)
        if !DeviceCapability.canOpenLivePreview(dev.devId) {
            showToast("该设备不支持预览")
            return
        }
        // 门铃 / 视频锁走门铃面板，其余走实时预览面板
        let vc: UIViewController = (DeviceCapability.resolveDeviceType(dev.devId) == 2)
            ? CameraDoorBellViewController(devId: dev.devId)
            : CameraPanelViewController(devId: dev.devId)
        navigationController?.pushViewController(vc, animated: true)
    }
    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let dev = devices[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let remove = UIAction(title: "移除设备", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self.confirmRemove(dev.devId)
            }
            return UIMenu(title: "", children: [remove])
        }
    }

    private func confirmRemove(_ devId: String) {
        confirm(title: "移除设备", message: "确定从家庭中移除该设备？") { [weak self] in
            ThingSmartDevice(deviceId: devId)?.remove({ [weak self] in
                DispatchQueue.main.async { self?.showToast("移除成功"); self?.loadDevices() }
            }, failure: { [weak self] error in
                DispatchQueue.main.async { self?.showError(code: nil, message: error?.localizedDescription) }
            })
        }
    }
}
