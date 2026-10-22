import UIKit
import AVKit
import ThingSmartHomeKit
import ThingSmartMessageKit

/// 视频消息（对应 Android CameraVideoMessageActivity）：
/// 用 ThingSmartMessage.fetchDetailList 拉取本设备告警消息明细，
/// 筛选带视频附件（attachPicList 中 isVideo）的消息，点击播放。
final class CameraVideoMessageViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let devId: String
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    /// 带视频附件的消息
    private var videos: [(msg: ThingSmartMessageListModel, videoUrl: String)] = []

    init(devId: String) {
        self.devId = devId
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "视频消息"
        view.backgroundColor = .white
        setupUI()
        loadMessages()
    }

    private func setupUI() {
        tableView.dataSource = self; tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "vmsg")
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        emptyLabel.text = "暂无视频消息"; emptyLabel.textColor = .gray; emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func loadMessages() {
        let message = ThingSmartMessage()
        let request = ThingSmartMessageDetailListRequestModel()
        request.msgType = .alarm
        request.msgSrcId = devId      // 按设备 id 过滤
        request.limit = 100
        request.offset = 0
        message.fetchDetailList(with: request, success: { [weak self] (list: [ThingSmartMessageListModel]?) in
            DispatchQueue.main.async {
                guard let self = self else { return }
                var result: [(ThingSmartMessageListModel, String)] = []
                for m in (list ?? []) {
                    if let url = m.attachPicList.first(where: { $0.isVideo && !$0.url.isEmpty })?.url {
                        result.append((m, url))
                    }
                }
                self.videos = result
                self.tableView.reloadData()
                self.emptyLabel.isHidden = !self.videos.isEmpty
            }
        }, failure: { [weak self] (error: Error?) in
            DispatchQueue.main.async {
                self?.emptyLabel.isHidden = false
                self?.showError(code: nil, message: error?.localizedDescription)
            }
        })
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { videos.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "vmsg", for: indexPath)
        let item = videos[indexPath.row]
        cell.textLabel?.text = "\(item.msg.dateTime ?? "") · 视频消息"
        cell.detailTextLabel?.text = item.msg.msgContent ?? "点击播放视频"
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let url = URL(string: videos[indexPath.row].videoUrl) else {
            showToast("暂无可播放的视频地址"); return
        }
        let player = AVPlayer(url: url)
        let vc = AVPlayerViewController(); vc.player = player
        present(vc, animated: true) { player.play() }
    }
}
