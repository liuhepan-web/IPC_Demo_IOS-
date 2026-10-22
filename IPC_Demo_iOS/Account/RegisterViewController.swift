import UIKit
import ThingSmartHomeKit

/// 注册页（对应 Android RegisterActivity）。
/// 先获取验证码，再注册账号。
final class RegisterViewController: UIViewController {

    private let countryCodeField = UITextField()
    private let accountField = UITextField()
    private let passwordField = UITextField()
    private let codeField = UITextField()
    private let codeButton = UIButton(type: .system)
    private let registerButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "注册"
        view.backgroundColor = UIColor(hex: TuyaConfig.bgGray)
        setupUI()
    }

    private func setupUI() {
        countryCodeField.placeholder = "国家码（如 86）"; countryCodeField.text = "86"; countryCodeField.borderStyle = .roundedRect
        accountField.placeholder = "账号（手机 / 邮箱）"; accountField.borderStyle = .roundedRect
        passwordField.placeholder = "密码"; passwordField.isSecureTextEntry = true; passwordField.borderStyle = .roundedRect
        codeField.placeholder = "验证码"; codeField.borderStyle = .roundedRect
        [countryCodeField, accountField, passwordField, codeField].forEach { $0.backgroundColor = .white; $0.heightAnchor.constraint(equalToConstant: 44).isActive = true }

        codeButton.setTitle("获取验证码", for: .normal)
        codeButton.applySecondary()
        codeButton.addTarget(self, action: #selector(onGetCode), for: .touchUpInside)

        registerButton.setTitle("注册", for: .normal)
        registerButton.applyPrimary()
        registerButton.addTarget(self, action: #selector(onRegister), for: .touchUpInside)

        let codeRow = UIStackView(arrangedSubviews: [codeField, codeButton])
        codeRow.axis = .horizontal
        codeRow.spacing = 12
        codeButton.setContentHuggingPriority(.required, for: .horizontal)

        let card = UIStackView(arrangedSubviews: [countryCodeField, accountField, passwordField, codeRow, registerButton])
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

    @objc private func onGetCode() {
        guard let countryCode = countryCodeField.text?.trimmingCharacters(in: .whitespaces),
              let account = accountField.text?.trimmingCharacters(in: .whitespaces),
              !countryCode.isEmpty, !account.isEmpty else {
            showToast("请输入国家码与账号")
            return
        }
        ThingSmartUser.sharedInstance().sendVerifyCode(withUserName: account,
            countryCode: countryCode, type: 0,
            success: { [weak self] in self?.showToast("验证码已发送") },
            failure: { [weak self] error in self?.showError(code: nil, message: error?.localizedDescription) })
    }

    @objc private func onRegister() {
        guard let countryCode = countryCodeField.text?.trimmingCharacters(in: .whitespaces),
              let account = accountField.text?.trimmingCharacters(in: .whitespaces),
              let password = passwordField.text, let code = codeField.text?.trimmingCharacters(in: .whitespaces),
              !countryCode.isEmpty, !account.isEmpty, !password.isEmpty, !code.isEmpty else {
            showToast("请完整填写注册信息")
            return
        }
        let isEmail = account.contains("@")
        let success: () -> Void = { [weak self] in
            DispatchQueue.main.async {
                self?.showToast("注册成功")
                self?.navigationController?.popViewController(animated: true)
            }
        }
        let failure: (Error?) -> Void = { [weak self] error in
            DispatchQueue.main.async { self?.showError(code: nil, message: error?.localizedDescription) }
        }
        if isEmail {
            ThingSmartUser.sharedInstance().register(byEmail: countryCode, email: account, password: password, code: code, success: success, failure: failure)
        } else {
            ThingSmartUser.sharedInstance().register(byPhone: countryCode, phoneNumber: account, password: password, code: code, success: success, failure: failure)
        }
    }
}
