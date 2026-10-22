import UIKit
import ThingSmartHomeKit

/// IPC 文档要求：视频出流后退到后台再回前台可能触发 SIGPIPE 导致崩溃，忽略该信号即可。
let sigpipeHandler: @convention(c) (Int32) -> Void = { _ in }

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 0) 忽略 SIGPIPE，避免后台切回前台时崩溃（IPC SDK 官方要求）
        signal(SIGPIPE, sigpipeHandler)

        // 1) 初始化涂鸦智能生活 SDK（对应 Android ThingHomeSdk.init）
        // 5.x 起 sharedInstance() 返回非可选值；密钥直接内联（勿提交到公开仓库）
        ThingSmartSDK.sharedInstance().start(withAppKey: "5jmaqm3t73mx3axk9mp3",
                                             secretKey: "nkmetfcaccvr5v9rs4ceexgeugkkj8yj")

        #if DEBUG
        ThingSmartSDK.sharedInstance().debugMode = true
        #endif

        // 2) 建立窗口（不使用 Scene，单一 window 对应 Android 单 Activity 模型）
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.makeKeyAndVisible()
        routeToRoot()

        return true
    }

    /// 根据登录态切换到登录页或主控台（对应 Android LoginActivity / MainActivity 的互斥流转）
    func routeToRoot() {
        let root: UIViewController
        if ThingSmartUser.sharedInstance().isLogin {
            root = MainViewController()
        } else {
            root = LoginViewController()
        }
        let nav = UINavigationController(rootViewController: root)
        nav.navigationBar.tintColor = UIColor(named: "AccentColor") ?? .systemBlue
        window?.rootViewController = nav
    }

    /// 退出登录后回到登录页
    func logoutAndRoute() {
        ThingSmartUser.sharedInstance().loginOut({
            SessionManager.clearCurrentHome()
            DispatchQueue.main.async { [weak self] in
                self?.routeToRoot()
            }
        })
    }

    // 横屏全屏：把「本窗口允许的方向」交给当前最上层 VC 决定。
    // CameraPanelViewController 在全屏时返回 .landscape，其它页面默认 .portrait，
    // 从而既不破坏其它界面竖屏，又能让预览页真正横过来。
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        (window?.rootViewController?.topMostPresented.supportedInterfaceOrientations) ?? .portrait
    }
}

// MARK: - 找到真正显示在屏幕上的最顶层 VC（导航栈 / 模态 / Tab 递归）
extension UIViewController {
    var topMostPresented: UIViewController {
        if let presented = presentedViewController {
            return presented.topMostPresented
        }
        if let nav = self as? UINavigationController, let top = nav.topViewController {
            return top.topMostPresented
        }
        if let tab = self as? UITabBarController, let sel = tab.selectedViewController {
            return sel.topMostPresented
        }
        return self
    }
}
