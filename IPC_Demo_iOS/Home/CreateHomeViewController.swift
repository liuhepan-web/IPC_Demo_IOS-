import UIKit
import ThingSmartHomeKit

/// 创建家庭（对应 Android CreateHomeActivity）。创建后自动设为当前家庭。
final class CreateHomeViewController: UIViewController {

    private let nameField = UITextField()
    private let cityField = UITextField()
    private let doneButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "创建家庭"
        view.backgroundColor = UIColor(hex: TuyaConfig.bgGray)
        setupUI()
    }

    private func setupUI() {
        nameField.placeholder = "家庭名称"; nameField.borderStyle = .roundedRect; nameField.backgroundColor = .white
        cityField.placeholder = "城市（如 上海）"; cityField.borderStyle = .roundedRect; cityField.backgroundColor = .white
        [nameField, cityField].forEach { $0.heightAnchor.constraint(equalToConstant: 44).isActive = true }

        doneButton.setTitle("创建", for: .normal); doneButton.applyPrimary()
        doneButton.addTarget(self, action: #selector(onDone), for: .touchUpInside)

        let card = UIStackView(arrangedSubviews: [nameField, cityField, doneButton])
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

    @objc private func onDone() {
        guard let name = nameField.text?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
              let city = cityField.text?.trimmingCharacters(in: .whitespaces), !city.isEmpty else {
            showToast("请输入家庭名称与城市")
            return
        }
        // 经纬度示例（上海），实际可接定位
        // 5.x：ThingSmartHomeManager 为实例化使用（无 sharedInstance）
        ThingSmartHomeManager().addHome(withName: name,
            geoName: city, rooms: [], latitude: 30.40, longitude: 120.52,
            success: { [weak self] (homeId: Int64) in
                SessionManager.setCurrentHome(homeId)
                DispatchQueue.main.async {
                    self?.showToast("创建成功")
                    self?.navigationController?.popViewController(animated: true)
                }
            }, failure: { [weak self] (error: Error?) in
                DispatchQueue.main.async { self?.showError(code: nil, message: error?.localizedDescription) }
            })
    }
}
