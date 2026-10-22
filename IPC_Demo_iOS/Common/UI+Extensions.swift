import UIKit

extension UIViewController {

    /// 统一弹错误提示（对应 Android 的 Toast / error_with_code）
    func showToast(_ message: String) {
        let toast = UILabel()
        toast.text = message
        toast.textColor = .white
        toast.font = .systemFont(ofSize: 14)
        toast.textAlignment = .center
        toast.numberOfLines = 0
        toast.backgroundColor = UIColor(white: 0, alpha: 0.8)
        toast.layer.cornerRadius = 8
        toast.clipsToBounds = true
        toast.alpha = 0
        view.addSubview(toast)
        toast.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            toast.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
        UIView.animate(withDuration: 0.25, animations: { toast.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.25, delay: 1.8, options: [], animations: { toast.alpha = 0 }) { _ in
                toast.removeFromSuperview()
            }
        }
    }

    func showError(code: String?, message: String?) {
        let text = [code, message].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " : ")
        showToast(text.isEmpty ? "操作失败" : text)
    }

    /// 通用「确认」对话框（对应 Android AlertDialog）
    func confirm(title: String, message: String, ok: String = "确定",
                handler: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: ok, style: .destructive) { _ in handler() })
        present(alert, animated: true)
    }
}

extension UIColor {
    convenience init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

extension UIButton {
    /// 主色按钮样式（对应 Android MaterialButton 强调色）
    func applyPrimary() {
        backgroundColor = UIColor(hex: TuyaConfig.brandMain)
        setTitleColor(.white, for: .normal)
        layer.cornerRadius = 8
        titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
    }

    func applySecondary() {
        backgroundColor = UIColor(hex: TuyaConfig.bgGray)
        setTitleColor(UIColor(hex: TuyaConfig.brandDark), for: .normal)
        layer.cornerRadius = 8
        titleLabel?.font = .systemFont(ofSize: 15)
        contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
    }
}
