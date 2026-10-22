import Foundation
import ThingSmartHomeKit

/// 设备能力判定（对应 Android IpcDeviceHelper）。
/// 门铃 / 视频锁 / 低功耗设备不一定通过 isIPCDevice 判定，但同样支持 P2P 预览。
enum DeviceCapability {

    /// 设备归类：0 其他 / 1 IPC / 2 门铃或低功耗
    static func resolveDeviceType(_ devId: String) -> Int {
        let model = ThingSmartDevice(deviceId: devId)?.deviceModel
        let category = (model?.category ?? "").lowercased()
        let name = (model?.name ?? "").lowercased()
        if category.contains("doorbell") || name.contains("doorbell")
            || category.contains("video_lock") || name.contains("videolock") {
            return 2
        }
        if category.contains("ipc") || category.contains("camera") {
            return 1
        }
        // 有预览能力的设备归为 IPC
        return canOpenLivePreview(devId) ? 1 : 0
    }

    /// 是否允许进入实时预览（对应 IpcDeviceHelper.canOpenLivePreview）
    static func canOpenLivePreview(_ devId: String) -> Bool {
        guard !devId.isEmpty else { return false }
        let model = ThingSmartDevice(deviceId: devId)?.deviceModel
        let category = (model?.category ?? "").lowercased()
        if category.contains("ipc") || category.contains("camera")
            || category.contains("doorbell") || category.contains("video_lock") {
            return true
        }
        // 兜底：存在 deviceModel 即尝试预览
        return model != nil
    }

    static func typeLabel(_ devId: String) -> String {
        switch resolveDeviceType(devId) {
        case 2: return "门铃"
        case 1: return "摄像机"
        default: return "其他"
        }
    }
}
