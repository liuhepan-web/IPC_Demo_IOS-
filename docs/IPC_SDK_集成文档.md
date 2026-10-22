# IPC Demo (iOS) · SDK 集成文档

> 与当前工程（`com.ipc.test.set`，Swift 5 + 涂鸦 Smart Life App SDK 5.0 / ThingSmart 7.8.x + 摄像机 IPC SDK）同步。  
> 操作与 UI 示意见：[IPC_Demo_操作文档.md](./IPC_Demo_操作文档.md)  
> 离线日志（目录、导出、易错点）：[IPC_离线日志集成文档.md](./IPC_离线日志集成文档.md)  
> 官方入口：[IPC 业务概述](https://developer.tuya.com/cn/docs/app-development/overview?id=Ka6km92o4do96) · [App SDK 集成](https://developer.tuya.com/cn/docs/app-development/integrated?id=Ka69nt96cw0uj)  
> 5.0 SDK 指南见仓库根目录 `README-zh.md` / `README-en.md`。

---

## 1. 工程概况

| 项 | 说明 |
|----|------|
| 工程描述 | `project.yml`（XcodeGen）+ `Podfile`（CocoaPods） |
| Bundle ID | `com.ipc.test.set` |
| 语言 | Swift 5 |
| 部署目标 | `project.yml` 声明 iOS 13.0；`Podfile` 声明 `platform :ios, '11.0'`（以 XcodeGen 产物为准） |
| 安全 SDK | `ThingSmartCryption`（5.0 唯一安全 SDK，无需 `t_s.bmp` 安全图） |
| App SDK | `ThingSmartHomeKit`（账号 / 家庭 / 配网 / 设备，版本对齐 7.8.x） |
| IPC SDK | `ThingSmartCameraKit`（预览 / 回放 / 云存储 / 门铃） |

### 1.1 源码结构

```text
IPC_Demo_iOS/
├── App/AppDelegate.swift                  # ThingSmartSDK 初始化 + 窗口 + 方向转发 + SIGPIPE
├── Common/
│   ├── TuyaConfig.swift                   # appKey/appSecret（Info.plist 优先）、配色、时间轴间隔
│   ├── DPConstants.swift                  # 设备 DP 码（101/103/104/106/109/110/116/119…）
│   ├── IpcLocalMediaHelper.swift          # 截图/录像落盘到 App 沙盒
│   └── UI+Extensions.swift               # 按钮/布局便捷扩展
├── Account/
│   ├── LoginViewController.swift          # 登录（国家码+账号+密码）
│   └── RegisterViewController.swift       # 注册（验证码）
├── Home/
│   ├── MainViewController.swift           # 控制台
│   ├── CreateHomeViewController.swift     # 创建家庭
│   ├── HomeListViewController.swift       # 家庭列表
│   └── DeviceListViewController.swift     # 设备列表（点进预览 / 长按移除）
├── Config/
│   ├── EzConfigViewController.swift       # EZ 配网
│   ├── ApConfigViewController.swift       # AP 配网
│   └── QrConfigViewController.swift       # 摄像头二维码配网
├── IPC/                                   # 摄像机能力
│   ├── CameraPanelViewController.swift    # 实时预览面板（核心 UI）
│   ├── CameraController.swift             # CameraController + CameraSessionManager（能力封装）
│   ├── CameraAlbumViewController.swift     # 本地相册
│   ├── CameraPlaybackViewController.swift # SD 卡录像 + 时间轴
│   ├── CameraSdManageViewController.swift # 存储卡管理
│   ├── CameraMessageViewController.swift  # 消息中心
│   ├── CameraVideoMessageViewController.swift
│   ├── CameraCloudStorageViewController.swift
│   ├── CameraDoorBellViewController.swift # 门铃
│   ├── DoorbellCallManager.swift
│   └── OfflineLogViewController.swift     # 离线日志导出
└── Models/
    ├── DeviceCapability.swift             # 设备能力位判断
    └── SessionManager.swift              # 登录态 / 当前家庭
```

---

## 2. 平台侧准备

1. [涂鸦 IoT 平台](https://iot.tuya.com/) 创建 App，获取 AppKey / AppSecret。  
2. Bundle ID 绑定 `com.ipc.test.set`。  
3. 构建并下载 **iOS 5.0 安全 SDK** `ios_core_sdk.tar.gz`，解压出 `Build/` 与 `ThingSmartCryption.podspec`，放在 `Podfile` 同级目录。

---

## 3. 工程生成与依赖安装

```bash
# 1) 由 project.yml 生成 .xcodeproj（需安装 xcodegen）
xcodegen generate

# 2) 安装 Pod（生成 .xcworkspace）
pod install

# 3) 之后一律用 .xcworkspace 打开，不要用 .xcodeproj
open IPC_Demo_iOS.xcworkspace
```

`Podfile` 的三个 source 缺一不可（参照官方 demo tuya-home-ios-sdk-sample-objc）：

```ruby
source 'https://cdn.cocoapods.org/'
source 'https://github.com/tuya/TuyaPublicSpecs.git'
source 'https://github.com/tuya/tuya-pod-specs.git'
```

依赖声明：

```ruby
platform :ios, '11.0'
use_frameworks!

target 'IPC_Demo_iOS' do
  pod "ThingSmartCryption", :path => './'   # 5.0 安全 SDK（解压到 Podfile 同级）
  pod "ThingSmartHomeKit", '~> 7.8.0'       # 智能生活 App SDK
  pod "ThingSmartCameraKit"                 # 摄像机 IPC SDK
end
```

- M 系列芯片模拟器需 Rosetta（`EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64`）。  
- 建议用真机验证 P2P，模拟器架构下部分能力不完整。

---

## 4. AppKey / AppSecret

`App/AppDelegate.swift` 在 `application(_:didFinishLaunchingWithOptions:)` 中初始化：

```swift
ThingSmartSDK.sharedInstance().start(withAppKey: <#appKey#>,
                                     secretKey: <#appSecret#>)
```

密钥两种配置方式（优先 `Info.plist`）：

- **方式 A（推荐，勿提交明文）**：在 `Info.plist` 增加键 `TuyaAppKey` / `TuyaAppSecret`，运行时由 `TuyaConfig.appKey / .appSecret` 读取；
- **方式 B（快速调试）**：直接改 `AppDelegate` 与 `TuyaConfig` 里的常量。

> ⚠️ 不要把 AppKey / AppSecret 明文提交到公开仓库；安全 SDK `Build/` 同样禁止外泄。

---

## 5. Application 初始化

`App/AppDelegate.swift` 关键步骤：

```swift
// 0) 忽略 SIGPIPE：视频出流后退到后台再回前台可能触发，忽略即可（IPC SDK 官方要求）
signal(SIGPIPE, SIG_IGN)

// 1) 初始化涂鸦智能生活 SDK
ThingSmartSDK.sharedInstance().start(withAppKey: ..., secretKey: ...)

// 2) 建立窗口（不使用 UIScene，单一 window 对应 Android 单 Activity 模型）
window = UIWindow(frame: UIScreen.main.bounds)
window?.makeKeyAndVisible()
routeToRoot()   // 按登录态切登录页 / 控制台
```

`#if DEBUG` 下会打开 `ThingSmartSDK.sharedInstance().debugMode = true`（App 级日志，与摄像机 SDK 的 `debugMode` 是两套，互不影响）。

**摄像机 SDK 调试日志**：`CameraController.init` 中 `ThingSmartCameraSDK.sharedInstance.debugMode = false`。  
⚠️ 设为 `true` 会让 SDK 对**每一帧**音视频包打印 `PushVideoPacket/PushAudioPacket`，每秒数百条同步日志占满主线程 → **预览卡顿 + 按钮点不动**。排查拉流/解码问题时才临时改回 `true`。

---

## 6. 权限

`Info.plist`（由 `project.yml` 注入）已声明：

- `NSMicrophoneUsageDescription`：对讲需要麦克风
- `NSCameraUsageDescription`：二维码配网 / 本地相册展示
- `NSPhotoLibraryUsageDescription`：浏览与保存本地截图 / 录像
- `NSAppTransportSecurity → NSAllowsArbitraryLoads: true`

对讲前动态申请麦克风；配网常需定位 / 本地网络权限。

---

## 7. 核心能力与代码映射

### 7.1 账号 / 家庭 / 配网

| 能力 | Demo |
|------|------|
| 登录 / 注册 | `LoginViewController` / `RegisterViewController` |
| 家庭 | `MainViewController` / `CreateHomeViewController` / `HomeListViewController` |
| EZ / AP | `EzConfigViewController` / `ApConfigViewController` |
| 二维码配网 | `QrConfigViewController` |
| 设备列表 / 移除 | `DeviceListViewController` → `removeDevice` |

### 7.2 实时预览（核心）

会话生命周期由 `CameraController` + `CameraSessionManager` 统一管理：

```text
CameraSessionManager.acquire(devId:)   →  ThingSmartCameraFactory.camera(withP2PType:deviceId:delegate:)
  → camera.connect?(with: .auto)
  → camera.startPreview()
  → cameraDidBeginPreview 回调里由 SDK 取 videoView() 挂到界面
```

要点：

- **p2pType 必须动态读取**：`model.p2pType()`（1=TUTK / 2=PPCS / 3=THING）。硬编码 `3` 会让非 THING 设备连错 P2P 栈而拉不到流。见 `CameraController.resolveP2PType`。
- **connect 幂等**：`CameraSessionManager.acquire` 对同一 `devId` 复用会话、只幂等 connect 一次；`viewDidAppear` 重复进入不再开新通道（修复「多次进出后卡死」）。
- **释放唯一入口 `teardown()`**：停流 → 断连 → `uninstallVideoRenderView` → 摘渲染视图 → 丢 camera 对象（修复「GL 上下文越堆越重」）。
- 引用计数归零后延迟 30s 才真正释放，去「本地相册 / 消息」这类无关页再返回可原样复用、不重连、不闪黑屏；明确退出（`isMovingFromParent`）时立即释放。
- 退到后台断通道、回前台自动重连（仅当仍有页面持有会话）。

### 7.3 声音 / 对讲与「已停止预览」修复（重点）

iOS 上 SDK 连上后会自动初始化音频会话。**若 App 未预先设置音频类别**，SDK 内部配置失败，会把整条连接拖崩 → P2P 反复重连 → 每次断开都触发 `cameraDidStopPreview`，即你看到的「已停止预览」闪现。

修复（涂鸦官方 IPC Demo 标准做法）：在进页面（`viewDidLoad` / `viewWillAppear`）以及每次切换声音/对讲**之前**，先主动预设：

```swift
try AVAudioSession.sharedInstance()
    .setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers])
try AVAudioSession.sharedInstance().setActive(true,
    options: .notifyOthersOnDeactivation)
```

设置成功后：连接稳定不再重连 → 「已停止预览」不再出现，且**声音（扬声器）与对讲（麦克风）均正常，与 Android 行为一致**。

> 日志佐证：`AVAudioSession_iOS.mm Failed to set mode: -50` / `category option 'defaultToSpeaker' is only applicable with category 'playAndRecord'` 即属于未预设该类别的典型报错。

### 7.4 缩放与横屏

| 交互 | 实现 |
|------|------|
| 双指捏合 | `CameraController.zoom(scale)`，对预览视图做视觉 `transform` 缩放，约 1.0～4.0 |
| 双击放大 | `ThingSmartCameraType` 默认支持双击缩放 |
| 竖屏 | 预览按 16:9 布局 |
| 横屏全屏 | `CameraPanelViewController` 隐藏底部控制区、预览铺满并 `transform` 旋转成横屏观感；方向由 `AppDelegate.supportedInterfaceOrientationsFor` 转发给当前最上层 VC |

> 横屏采用「容器 transform 旋转」而非 `UIDevice.setValue` 私有 API——后者在 iOS 26 会触发 `BUG IN CLIENT OF UIKIT` 断言。

### 7.5 预览控制

| 功能 | Demo |
|------|------|
| 静音 / 开启声音 | `camera.enableMute(_:for: .preview)`（切前先预设 AVAudioSession） |
| 清晰度 | `camera.setDefinition(.high / .standard)` |
| 对讲 | `camera.startAudioTalk()` / `stopAudioTalk()`（需麦克风） |
| 截图 | `camera.snapShoot()` → `IpcLocalMediaHelper.saveImage`（落 App 沙盒，编码在后台队列） |
| 本地录像 | `camera.startRecord?(withFilePath:)` / `stopRecord()` |
| 本地相册 | `CameraAlbumViewController` |

云存储门控：通过 `DeviceCapability` 判断设备是否支持云存储，不支持则不显示入口。

### 7.6 其它

| 功能 | 类 / 文件 |
|------|-----------|
| SD 管理 | `CameraSdManageViewController` |
| 卡录像 + 时间轴 | `CameraPlaybackViewController`（`queryRecordDays` / `queryRecordTimeSlice` / `enterPlayback` / `startPlayback`） |
| 消息 | `CameraMessageViewController`（DP 134/106 + 告警图/视频） |
| 离线日志 | `OfflineLogViewController`（导出沙盒 `com.tuya.smart/log`）；详见 [离线日志集成文档](./IPC_离线日志集成文档.md) |
| 云存储 | `CameraCloudStorageViewController` |
| 门铃 | `CameraDoorBellViewController` + `DoorbellCallManager` |

---

## 8. 集成到自有 App 的最小清单

1. 平台：Bundle ID 绑定 + 下载 5.0 安全 SDK `Build/` + `ThingSmartCryption.podspec` 放 Podfile 同级。  
2. `Podfile`：三个 source + `ThingSmartCryption`(path) + `ThingSmartHomeKit`(~>7.8.0) + `ThingSmartCameraKit`；`pod install` 后用 `.xcworkspace`。  
3. `AppDelegate`：`signal(SIGPIPE, SIG_IGN)` → `ThingSmartSDK.sharedInstance().start(withAppKey:secretKey:)` → 建窗口。  
4. 密钥走 `Info.plist`（TuyaAppKey/TuyaAppSecret），勿明文入库。  
5. 预览前动态读取 `p2pType` 并传给 `ThingSmartCameraFactory.camera(withP2PType:deviceId:delegate:)`。  
6. **进预览/切声音/对讲前预设 `AVAudioSession(.playAndRecord + .defaultToSpeaker)`**，否则会反复「已停止预览」。  
7. `cameraDidBeginPreview` 回调里由 SDK 取 `videoView()` 挂到界面；退出页用统一 `teardown()` 释放。  
8. 能力位门控 UI（对讲 / 云台 DP / 云存储）。  
9. 预览与回放切换时通过会话引用计数释放 P2P。  
10. 横屏用容器 transform，勿用 `UIDevice` 私有 API。

---

## 9. 常见问题

| 现象 | 可能原因 / 处理 |
|------|----------------|
| 预览黑屏 | 非 IPC、离线、P2P 失败、p2pType 不匹配、低功耗未唤醒、渲染视图未挂载 |
| **反复提示「已停止预览」** | 未预设 `AVAudioSession(.playAndRecord)` 导致 SDK 音频初始化失败、P2P 反复重连（见 7.3） |
| 预览卡顿 + 按钮点不动 | `ThingSmartCameraSDK.debugMode = true` 产生逐帧日志洪流，改为 `false` |
| 对讲无声 | 未授麦克风 / 未预设 playAndRecord / 设备不支持 |
| 云存储按钮不出现 | 设备不支持云存储（预期） |
| 卡回放 `-40201` / `-40205` | 未释放预览 P2P；或时间不在片段内 |
| 真机装不上 / 模拟器架构报错 | 模拟器需 Rosetta；建议真机；`Build/` 安全 SDK 需与 App 密钥匹配 |
| 打开工程后类找不到 | 必须用 `.xcworkspace`，而非 `.xcodeproj` |

---

## 10. 官方链接

- [App SDK 集成](https://developer.tuya.com/cn/docs/app-development/integrated?id=Ka69nt96cw0uj)
- [IPC 概述](https://developer.tuya.com/cn/docs/app-development/overview?id=Ka6km92o4do96)
- [音视频功能](https://developer.tuya.com/cn/docs/app-development/avfunction?id=Ka6nuvucjujar)
- [摄像头扫码配网](https://developer.tuya.com/cn/docs/app-development/camera-scan-code-network-configuration?id=Kaixkcv3adu8y)
- [5.0 SDK 指南](https://developer.tuya.com/cn/docs/app-development/migration_guide?id=Kci3zqm3wlcut)

操作文档：[IPC_Demo_操作文档.md](./IPC_Demo_操作文档.md)  
离线日志：[IPC_离线日志集成文档.md](./IPC_离线日志集成文档.md)  
内部交付摘要：[IPC_Demo_内部交付文档.md](./IPC_Demo_内部交付文档.md)
