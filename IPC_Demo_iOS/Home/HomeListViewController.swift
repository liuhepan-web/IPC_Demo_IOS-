import UIKit
import ThingSmartHomeKit

/// 家庭列表（对应 Android HomeListActivity）：展示家庭，点击切换当前家庭。
final class HomeListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var homes: [ThingSmartHomeModel] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "家庭列表"
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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadHomes()
    }

    private func loadHomes() {
        ThingSmartHomeManager().getHomeList { [weak self] (homes: [ThingSmartHomeModel]?) in
            DispatchQueue.main.async {
                self?.homes = homes ?? []
                self?.tableView.reloadData()
            }
        } failure: { [weak self] (error: Error?) in
            DispatchQueue.main.async { self?.showError(code: nil, message: error?.localizedDescription) }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { homes.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let home = homes[indexPath.row]
        let mark = home.homeId == SessionManager.currentHome() ? " ✓" : ""
        cell.textLabel?.text = "\(home.name)\(mark)"
        cell.detailTextLabel?.text = "ID: \(home.homeId)"
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let home = homes[indexPath.row]
        SessionManager.setCurrentHome(home.homeId)
        showToast("已选择：\(home.name)")
        tableView.reloadData()
    }
}
