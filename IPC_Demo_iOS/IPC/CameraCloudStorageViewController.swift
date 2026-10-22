import UIKit
import ThingSmartCameraKit

/// 云存储（对应 Android CameraCloudStorageActivity）：
/// 使用 ThingSmartCameraKit 真实暴露的 ThingSmartCloudManager：
///   · loadCloudData / reLoadCloudDays 查询云端有录像的日期
///   · timeEvents(with:offset:limit:...) 查询某天的事件列表
///   · playCloudVideo(withStartTime:...) 播放云端录像
final class CameraCloudStorageViewController: UIViewController {

    private let devId: String
    private let manager: ThingSmartCloudManager
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let statusLabel = UILabel()
    /// 云端事件（ThingSmartCloudTimeEventModel）
    private var events: [ThingSmartCloudTimeEventModel] = []
    /// 云端有录像的日期（ ThingSmartCloudDayModel.uploadDay，如 "2024-06-01"）
    private var cloudDays: [ThingSmartCloudDayModel] = []

    init(devId: String) {
        self.devId = devId
        self.manager = ThingSmartCloudManager(deviceId: devId)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "云存储"
        view.backgroundColor = .white
        setupUI()
        queryCloudDays()
    }

    private func setupUI() {
        statusLabel.text = "加载云端录像…"; statusLabel.textColor = .gray; statusLabel.textAlignment = .center
        view.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
        tableView.dataSource = self; tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cloud")
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - 云存储查询
    private func queryCloudDays() {
        guard ThingSmartCloudManager.isSupportCloudStorage(devId) else {
            statusLabel.text = "该设备未开通云存储服务"
            return
        }
        // loadCloudData 拉取鉴权与日期概览；state 标识服务状态
        manager.loadCloudData { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .validData, .expiredData:
                self.loadDays()
            default:
                DispatchQueue.main.async { self.statusLabel.text = "云端暂无可用录像 (state=\(state.rawValue))" }
            }
        }
    }

    private func loadDays() {
        manager.reLoadCloudDays { [weak self] cloudDays in
            guard let self = self else { return }
            self.cloudDays = cloudDays ?? []
            DispatchQueue.main.async {
                guard let day = cloudDays?.last else {
                    self.statusLabel.text = "本月云端暂无录像"
                    return
                }
                self.queryCloudEvents(dayModel: day)
            }
        }
    }

    private func queryCloudEvents(dayModel: ThingSmartCloudDayModel) {
        DispatchQueue.main.async { self.statusLabel.text = "加载 \(dayModel.uploadDay ?? "") 事件…" }
        manager.timeEvents(withCloudDay: dayModel, offset: 0, limit: 100,
                           success: { [weak self] timeEvents in
                               guard let self = self else { return }
                               DispatchQueue.main.async {
                                   self.events = timeEvents ?? []
                                   self.statusLabel.text = "\(dayModel.uploadDay ?? "") 共 \(self.events.count) 个云端事件"
                                   self.tableView.reloadData()
                               }
                           },
                           failure: { [weak self] error in
                               DispatchQueue.main.async {
                                   self?.statusLabel.text = "查询失败"
                                   self?.showError(code: nil, message: error?.localizedDescription)
                               }
                           })
    }

    private func playEvent(_ event: ThingSmartCloudTimeEventModel) {
        let start = Int(event.startTime)
        let end = Int(event.endTime)
        _ = manager.playCloudVideo(withStartTime: start,
                                   endTime: end,
                                   isEvent: true,
                                   onResponse: { _ in },
                                   onFinished: { _ in })
        showToast("已开始云端回放（事件级）")
    }
}

extension CameraCloudStorageViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { events.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cloud", for: indexPath)
        let e = events[indexPath.row]
        let time = Date(timeIntervalSince1970: TimeInterval(e.startTime))
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm:ss"
        cell.textLabel?.text = e.describe ?? f.string(from: time)
        cell.detailTextLabel?.text = "点击播放云端录像"
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        playEvent(events[indexPath.row])
    }
}
