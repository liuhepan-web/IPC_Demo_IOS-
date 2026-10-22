import UIKit
import ThingSmartHomeKit
import ThingSmartMessageKit

/// 消息中心（对应 Android CameraMessageActivity）：展示设备（移动侦测等）告警消息列表。
final class CameraMessageViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let devId: String
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private var messages: [ThingSmartMessageListModel] = []

    init(devId: String) {
        self.devId = devId
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "消息中心"
        view.backgroundColor = .white
        setupUI()
        loadMessages()
    }

    private func setupUI() {
        tableView.dataSource = self; tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "msg")
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        emptyLabel.text = "暂无消息"; emptyLabel.textColor = .gray; emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func loadMessages() {
        // 拉取告警类消息（移动侦测、低电量、防拆等），按设备过滤
        let message = ThingSmartMessage()
        let request = ThingSmartMessageListRequestModel()
        request.msgType = .alarm
        request.limit = 100
        request.offset = 0
        message.fetchList(with: request, success: { [weak self] (list: [ThingSmartMessageListModel]?) in
            DispatchQueue.main.async {
                self?.messages = (list ?? []).filter { $0.msgSrcId == self?.devId }
                self?.tableView.reloadData()
                self?.emptyLabel.isHidden = !(self?.messages.isEmpty ?? true)
            }
        }, failure: { [weak self] (error: Error?) in
            DispatchQueue.main.async {
                self?.emptyLabel.isHidden = false
                self?.showError(code: nil, message: error?.localizedDescription)
            }
        })
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { messages.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "msg", for: indexPath)
        let m = messages[indexPath.row]
        cell.textLabel?.text = "\(m.dateTime ?? "") · 告警"
        cell.detailTextLabel?.text = m.msgContent ?? ""
        return cell
    }
}
