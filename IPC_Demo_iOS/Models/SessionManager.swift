import Foundation

/// 当前家庭缓存（对应 Android HomeModel，用 SharedPreferences 存 homeId）。
/// iOS 用 UserDefaults 持久化，登录态由 ThingSmartUser 托管。
enum SessionManager {

    private static let currentHomeKey = "IPC_Demo_CurrentHomeId"

    static func setCurrentHome(_ homeId: Int64) {
        UserDefaults.standard.set(homeId, forKey: currentHomeKey)
    }

    static func currentHome() -> Int64 {
        let v = UserDefaults.standard.object(forKey: currentHomeKey)
        if let num = v as? Int64 { return num }
        if let num = v as? Int { return Int64(num) }
        return 0
    }

    static func clearCurrentHome() {
        UserDefaults.standard.removeObject(forKey: currentHomeKey)
    }
}
