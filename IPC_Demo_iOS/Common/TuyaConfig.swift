import Foundation

/// 全局配置：AppKey / AppSecret、配色、能力开关。
///
/// 密钥配置（二选一，优先 Info.plist）：
///   1. 在 Info.plist 增加键 TuyaAppKey / TuyaAppSecret；
///   2. 或直接在下方的 `appKey` / `appSecret` 常量里填写（注意勿提交到仓库）。
/// 包名 / Bundle ID 需与涂鸦 IoT 平台一致（Android 为 com.ipc.demo.set，iOS 可同用）。
enum TuyaConfig {

    /// 从 Info.plist 读取；读取不到则回退到下方常量。
    static var appKey: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "TuyaAppKey") as? String, !v.isEmpty {
            return v
        }
        return "5jmaqm3t73mx3axk9mp3"
    }

    static var appSecret: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "TuyaAppSecret") as? String, !v.isEmpty {
            return v
        }
        return "nkmetfcaccvr5v9rs4ceexgeugkkj8yj"
    }

    // MARK: - 配色（对应 Android 操作文档：顶栏 #1B2E3A / 主色 #1F6F8B / 强调 #D97706）
    static let brandDark  = "1B2E3A"
    static let brandMain  = "1F6F8B"
    static let brandAccent = "D97706"
    static let bgGray     = "EEF2F5"

    /// 回放时间轴刷新最小间隔（ms），避免每帧刷新卡 UI（对应 Android TIMELINE_UI_MIN_INTERVAL_MS）
    static let timelineRefreshInterval: TimeInterval = 0.4
}
