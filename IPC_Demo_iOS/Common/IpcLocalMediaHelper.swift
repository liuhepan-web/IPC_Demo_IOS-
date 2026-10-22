import Foundation
import Photos
import UIKit

/// 本地媒体保存（对应 Android IpcLocalMediaHelper）：
/// 截图 / 录像一方面落一份到 App 沙盒目录（供「本地相册」展示），另一方面写入系统相册。
enum IpcLocalMediaHelper {

    /// 媒体 I/O 专用串行队列：目录扫描、JPEG 编码、写盘都不能占主线程
    static let ioQueue = DispatchQueue(label: "com.ipc.demo.localmedia", qos: .utility)

    /// App 沙盒媒体目录（录像 / 截图同时落一份到这里，便于「本地相册」读取）。
    static var localMediaDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IPC_Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 保存截图 UIImage：写入沙盒 + 系统相册，返回沙盒文件 URL（可能为 nil）。
    /// 调用线程不限（建议在 ioQueue 上调用），内部不再切线程。
    @discardableResult
    static func saveImage(_ image: UIImage, devId: String) -> URL? {
        let name = "\(devId)_\(Self.timestamp()).jpg"
        let url = localMediaDir.appendingPathComponent(name)
        // jpegData 是 CPU 密集操作，放这里执行可避免预览掉帧
        if let data = image.jpegData(compressionQuality: 0.9) {
            try? data.write(to: url)
        }
        saveImageToPhotoLibrary(image)
        return url
    }

    /// 保存录像文件（沙盒路径）到系统相册。
    static func saveVideo(at fileURL: URL) {
        saveVideoToPhotoLibrary(fileURL)
    }

    /// 列举沙盒内已保存的媒体（对应 Android 本地相册扫描）。
    /// 修改点：先把每个文件的修改时间一次性读出来再排序，
    /// 原实现在比较器里反复读磁盘属性，文件一多就是 O(n log n) 次 I/O。
    static func listLocalMedia() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: localMediaDir,
                                                                  includingPropertiesForKeys: [.contentModificationDateKey],
                                                                  options: .skipsHiddenFiles)) ?? []
        let keyed = files.map {
            ($0, ($0.hasDirectoryPath ? nil : (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)) ?? Date.distantPast)
        }
        return keyed.sorted { $0.1 > $1.1 }.map { $0.0 }
    }

    // MARK: - 系统相册写入
    private static func isPhotoLibraryAuthorized() -> Bool {
        let status = PHPhotoLibrary.authorizationStatus()
        if #available(iOS 14, *) {
            return status == .authorized || status == .limited
        }
        return status == .authorized
    }

    /// 授权判断不再递归重试（未授权时静默跳过沙盒外的写入，避免反复弹权限与闭包堆积）
    private static func saveImageToPhotoLibrary(_ image: UIImage) {
        let perform = {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: nil)
        }
        guard isPhotoLibraryAuthorized() else {
            PHPhotoLibrary.requestAuthorization { status in
                let granted: Bool
                if #available(iOS 14, *) {
                    granted = status == .authorized || status == .limited
                } else {
                    granted = status == .authorized
                }
                if granted { perform() }
            }
            return
        }
        perform()
    }

    private static func saveVideoToPhotoLibrary(_ url: URL) {
        let perform = {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }, completionHandler: nil)
        }
        guard isPhotoLibraryAuthorized() else {
            PHPhotoLibrary.requestAuthorization { status in
                let granted: Bool
                if #available(iOS 14, *) {
                    granted = status == .authorized || status == .limited
                } else {
                    granted = status == .authorized
                }
                if granted { perform() }
            }
            return
        }
        perform()
    }

    /// 时间戳：用 DateComponents 直接拼，既避免每次新建 DateFormatter，
    /// 也不会像共享 formatter 那样有线程安全问题
    private static func timestamp() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date())
        return String(format: "%04d%02d%02d_%02d%02d%02d",
                      c.year ?? 1970, c.month ?? 1, c.day ?? 1, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}
