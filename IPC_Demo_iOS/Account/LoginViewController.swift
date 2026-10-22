import UIKit
import ThingSmartHomeKit

/// 登录页（对应 Android LoginActivity）。
/// 支持邮箱 / 手机号 + 密码；登录成功后跳转主控台。
final class LoginViewController: UIViewController {

    private let countryCodeField = UITextField()
    private let accountField = UITextField()
    private let passwordField = UITextField()
    private let loginButton = UIButton(type: .system)
    private let registerButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "IPC Demo"
        view.backgroundColor = UIColor(hex: TuyaConfig.bgGray)
        setupUI()
    }

    private func setupUI() {
        let header = UILabel()
        header.text = "Smart Life · IPC 演示"
        header.textColor = UIColor(hex: TuyaConfig.brandDark)
        header.font = .systemFont(ofSize: 22, weight: .bold)
        header.textAlignment = .center

        countryCodeField.placeholder = "国家码（如 86）"
        accountField.placeholder = "账号（手机 / 邮箱）"
        passwordField.placeholder = "密码"
        passwordField.isSecureTextEntry = true
        [countryCodeField, accountField, passwordField].forEach { f in
            f.borderStyle = .roundedRect
            f.backgroundColor = .white
            f.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }
        countryCodeField.text = "86"

        loginButton.setTitle("登录", for: .normal)
        loginButton.applyPrimary()
        loginButton.addTarget(self, action: #selector(onLogin), for: .touchUpInside)

        registerButton.setTitle("去注册 →", for: .normal)
        registerButton.setTitleColor(UIColor(hex: TuyaConfig.brandMain), for: .normal)
        registerButton.addTarget(self, action: #selector(onRegister), for: .touchUpInside)

        let card = UIStackView(arrangedSubviews: [header, countryCodeField, accountField, passwordField, loginButton, registerButton])
        card.axis = .vertical
        card.spacing = 14
        card.layoutMargins = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        card.isLayoutMarginsRelativeArrangement = true
        card.backgroundColor = .white
        card.layer.cornerRadius = 12
        card.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24)

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

    @objc private func onRegister() {
        navigationController?.pushViewController(RegisterViewController(), animated: true)
    }

    @objc private func onLogin() {
        guard let countryCode = countryCodeField.text?.trimmingCharacters(in: .whitespaces),
              let account = accountField.text?.trimmingCharacters(in: .whitespaces),
              let password = passwordField.text, !countryCode.isEmpty, !account.isEmpty, !password.isEmpty else {
            showToast("请输入国家码、账号与密码")
            return
        }
        let isEmail = account.contains("@")
        let user = ThingSmartUser.sharedInstance()
        let success: () -> Void = { [weak self] in
            DispatchQueue.main.async {
                self?.showToast("登录成功")
                (UIApplication.shared.delegate as? AppDelegate)?.routeToRoot()
            }
        }
        let failure: (Error?) -> Void = { [weak self] error in
            DispatchQueue.main.async { self?.showError(code: nil, message: error?.localizedDescription) }
        }
        if isEmail {
            user.login(byEmail: countryCode, email: account, password: password, success: success, failure: failure)
        } else {
            user.login(byPhone: countryCode, phoneNumber: account, password: password, success: success, failure: failure)
        }
    }
}
