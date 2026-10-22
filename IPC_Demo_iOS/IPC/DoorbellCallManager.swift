import UIKit
import ThingSmartHomeKit

/// 门铃来电管理（对应 Android DoorbellCallManager）：监听门铃设备 DP 上报，
/// 收到「来电」DP 时弹出接听界面；接听后复用 CameraController 建立对讲通道。
///
/// 说明：
/// - 生产环境门铃来电建议通过 Tuya 专属「门铃通话」能力（ThingSmartDoorbell / 推送）接收，
///   此处用 DP 上报演示完整接听->对讲链路，便于无硬件时也能跑通 UI。
/// - dp 编号请按设备物模型替换（下方 `doorbellDpId` 为示例值）。
final class DoorbellCallManager: NSObject, ThingSmartDeviceDelegate {

    static let shared = DoorbellCallManager()

    /// 门铃「来电」DP 编号（示例：dp 111。请按设备实际 DP 文档替换）
    private let doorbellDpId = "111"

    private var overlay: UIAlertController?

    /// 订阅某个门铃设备的 DP 上报
    func observe(devId: String) {
        ThingSmartDevice(deviceId: devId)?.delegate = self
    }

    // MARK: - ThingSmartDeviceDelegate
    func device(_ device: ThingSmartDevice!, dpsUpdate dps: [AnyHashable: Any]!) {
        guard let dps = dps, let value = dps[doorbellDpId] else { return }
        if "\(value)" == "1" {
            presentIncoming(devId: device.deviceModel.devId ?? "")
        }
    }

    private func presentIncoming(devId: String) {
        guard overlay == nil else { return }
        let alert = UIAlertController(title: "门铃来电", message: "是否接听？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "接听", style: .default) { [weak self] _ in
            self?.overlay = nil
            self?.answer(devId: devId)
        })
        alert.addAction(UIAlertAction(title: "拒接", style: .destructive) { [weak self] _ in
            self?.overlay = nil
        })
        topViewController()?.present(alert, animated: true)
        overlay = alert
    }

    private func answer(devId: String) {
        // 复用 CameraSessionManager 托管的会话：这里原来是自己 new CameraController，
        // 会与预览页各占一条设备并发会话，且永不释放（没有断开入口）。
        let ctrl = CameraSessionManager.shared.acquire(devId: devId, delegate: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak ctrl] in ctrl?.startTalk() }
        // 本 Demo 没有挂断入口：立即把引用还给管理器，由空闲计时器在 30 秒后释放通道；
        // 若预览页此时仍持有会话（refs > 0），不会被释放。
        CameraSessionManager.shared.release(devId: devId, delegate: nil, immediate: false)
        topViewController()?.showToast("已接听，对讲已开启")
    }

    private func topViewController() -> UIViewController? {
        var vc = UIApplication.shared.keyWindow?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
