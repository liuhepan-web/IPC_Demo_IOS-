# IPC Demo (iOS) · 离线日志集成文档

> 与当前工程（`com.ipc.test.set`，Swift 5 + 涂鸦 Smart Life App SDK 5.0）同步。  
> 总集成文档：[IPC_SDK_集成文档.md](./IPC_SDK_集成文档.md) · 操作说明：[IPC_Demo_操作文档.md](./IPC_Demo_操作文档.md)  
> 官方文档：[日志说明](https://developer.tuya.com/cn/docs/app-development/ipcsdklog?id=Kbvezkn5bkaam)

离线日志解决的问题：真机调试时无法一直连着 Xcode 抓日志，问题又只在特定环境下复现。接入后，SDK 会把运行日志写到 **App 沙盒**，复现后导出文件提交涂鸦工单即可联调。

**iOS 与 Android 的差异**：Android 用 `TLogSDK` 落加密文件；iOS 5.0 SDK 未提供等价的加密上传 API，日志由 `ThingSmartSDK` 直接写到沙盒 `Cache/com.tuya.smart/log`，Demo 通过系统分享表导出。两者目标一致（拿到可提交的日志文件），但机制不同，勿混用。

---

## 1. Demo 中对应代码

| 步骤 | Demo 位置 |
|------|-----------|
| App 级日志开关 | `App/AppDelegate.swift` → `#if DEBUG` 下 `ThingSmartSDK.sharedInstance().debugMode = true` |
| 摄像机级日志开关 | `IPC/CameraController.swift` → `ThingSmartCameraSDK.sharedInstance.debugMode = false`（**默认关闭**，避免逐帧日志卡顿） |
| 查询 / 导出 / 分享 | `IPC/OfflineLogViewController.swift` |
| 页面入口 | `Home/MainViewController`「离线日志」 |
| 日志落盘目录 | `<App Container>/Library/Caches/com.tuya.smart/log` |

最小接入只需：确认 `ThingSmartSDK` 已初始化（AppDelegate），日志即自动落盘；导出 UI 可按自有 App 改。

---

## 2. 日志去哪了

iOS 没有「下载/IPCDemo_logs」这种公开落点。日志在 **App 沙盒 Cache 目录**，系统文件管理器默认看不到：

```text
<App Container>/Library/Caches/com.tuya.smart/log
```

`OfflineLogViewController` 在 `viewDidLoad` 里展示的就是这个路径，并列出其中文件：

```swift
let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
let logDir = cache?.appendingPathComponent("com.tuya.smart/log", isDirectory: true)
```

---

## 3. 把文件拿出来（Demo 的做法）

`OfflineLogViewController.onUpload()` 直接调系统分享表 `UIActivityViewController`，把日志目录信息（路径 + 文件列表）分享到微信 / 邮件 / AirDrop 等：

```swift
let vc = UIActivityViewController(activityItems: [content], applicationActivities: nil)
vc.popoverPresentationController?.sourceView = view   // iPad 必须设 anchor
present(vc, animated: true)
```

| 方式 | 行为 | 说明 |
|------|------|------|
| 系统分享 | `UIActivityViewController` | 主路径；可选 AirDrop / 邮件 / 文件 App 保存 |
| 只读路径 | 页面顶部 label | 调试用，复制路径给测试 |

> iOS 沙盒下**不能**像 Android 那样用 MediaStore 写入公共「下载」目录；一切以系统分享 / 文件 App 为准。

---

## 4. 集成易错点

按出现频率排列。

### 4.1 在文件管理器「找不到日志」

预期行为，不是 SDK 坏了。文件在沙盒。必须：① 确认路径为 `Cache/com.tuya.smart/log`；② 通过系统分享导出；③ 再提交工单。

### 4.2 摄像机逐帧日志把 App 拖垮

`ThingSmartCameraSDK.sharedInstance.debugMode` 默认 `false`。**不要**为抓日志长期开 `true`——SDK 会对每帧音视频包打印，每秒数百条同步日志占满主线程，导致预览卡顿、按钮点不动。只在排查拉流/解码时临时改回 `true`，确认后改回 `false`。

### 4.3 `debugMode` 两套分不清

- `ThingSmartSDK.sharedInstance().debugMode`：App 级（账号/家庭/网络），Debug 开关即可；
- `ThingSmartCameraSDK.sharedInstance.debugMode`：摄像机级（音视频帧），**务必保持 `false`**。

两者互不影响。

### 4.4 iPad 上分享表崩溃

`UIActivityViewController` 在 iPad 必须设置 `popoverPresentationController.sourceView`（或 `barButtonItem`），否则 `popover` 无 anchor 会崩。Demo 已设 `sourceView = view`。

### 4.5 误把日志当明文可读

iOS 5.0 落盘的是 SDK 内部日志文件，部分可能非纯文本。提交工单时附上：复现时间、设备 ID、App 版本、操作步骤，与 Android 一致。

### 4.6 混淆后初始化/回调异常

Release 若开启混淆（Swift 一般靠 Bitcode/LLVM，OC 部分可能被 strip），确保 `ThingSmart*` 相关符号不被错误裁剪；如用 OC 桥接层，按需加 `-ObjC` 链接标志与 keep 规则。本 Demo Debug 直跑，接入方自测分享导出。

---

## 5. 接入自有 App 的检查清单

1. `AppDelegate` 中 `ThingSmartSDK` 已 `start(withAppKey:secretKey:)`。  
2. 确认日志目录为 `Cache/com.tuya.smart/log`（不同 SDK 版本可能微调子路径，先打印验证）。  
3. 提供「系统分享」或等价能力把日志导出；不要只展示私有路径。  
4. `ThingSmartCameraSDK.debugMode` 保持 `false`。  
5. iPad 分享表设好 `popover` anchor。  
6. 告知测试：复现后立刻导出、连同复现步骤提交工单。

---

## 6. 与 Android 的差异速查

| 项 | Android | iOS |
|----|---------|-----|
| 日志机制 | `TLogSDK` 加密落盘 | SDK 写沙盒 `Cache/com.tuya.smart/log` |
| 导出路径 | 下载/IPCDemo_logs（MediaStore） | 系统分享（UIActivityViewController） |
| 上传 API | `TLogSDK.fetchLogs` | 5.0 未提供，改为导出文件 |
| 摄像机日志开关 | `L.setLogInterception` + `TLogSDK` | `ThingSmartCameraSDK.debugMode`（保持 false） |

---

## 7. 官方链接

- [离线日志](https://developer.tuya.com/cn/docs/app-development/ipcsdklog?id=Kbvezkn5bkaam)
- [IPC 业务概述](https://developer.tuya.com/cn/docs/app-development/overview?id=Ka6km92o4do96)
- [App SDK 集成](https://developer.tuya.com/cn/docs/app-development/integrated?id=Ka69nt96cw0uj)
