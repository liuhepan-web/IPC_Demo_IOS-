import Foundation

/// IPC 相关 DP 点（与 Android DPConstants 保持一致）。
/// 来源：SD 卡 https://developer.tuya.com/cn/docs/app-development/sdcard
///       移动侦测 https://developer.tuya.com/cn/docs/app-development/datapointid
enum DP: String {
    // 云台
    case ptzControl      = "119"
    case ptzStop         = "116"
    // 水印
    case watermark       = "104"
    // 存储卡
    case sdCardRecordSwitch = "150"
    case sdCardRecordMode   = "151"
    case sdStatus            = "110"
    case sdStorage           = "109"
    case sdFormat            = "111"
    case sdFormatStatus      = "117"
    // 移动侦测
    case motionSwitch      = "134"
    case motionSensitivity = "106"

    // 云台方向（值：0 上 / 2 右 / 4 下 / 6 左，对应 Android PTZDPModel）
    enum PTZ: String {
        case up    = "0"
        case right = "2"
        case down  = "4"
        case left  = "6"
    }
}
