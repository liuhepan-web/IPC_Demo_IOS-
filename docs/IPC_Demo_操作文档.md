# IPC Demo (iOS) · 操作文档

> 与当前仓库代码同步（Swift 5 + 涂鸦 Smart Life App SDK 5.0 / ThingSmart 7.8.x + 摄像机 IPC SDK）。  
> 集成细节见：[IPC_SDK_集成文档.md](./IPC_SDK_集成文档.md)  
> 离线日志接入与易错点：[IPC_离线日志集成文档.md](./IPC_离线日志集成文档.md)  
> 内部一页纸交付摘要：[IPC_Demo_内部交付文档.md](./IPC_Demo_内部交付文档.md)（不上传 GitHub）

---

## 1. 运行前准备

1. Xcode（建议 15+）打开工程：**必须用 `.xcworkspace`**，不是 `.xcodeproj**。
2. 准备 5.0 安全 SDK `ios_core_sdk.tar.gz`：
   - 到涂鸦 IoT 平台 → 你的 App → 构建并下载「iOS 版本 SDK」；
   - 解压得到 `Build/`（App 专属安全 SDK）与 `ThingSmartCryption.podspec`，放在 `Podfile` 同级目录（即 `IPC_Demo_iOS/` 根）。
3. `pod install`（或 `pod update`）生成 `.xcworkspace`。
4. 配置 AppKey / AppSecret（两种方式二选一，见集成文档）：
   - 在 `Info.plist` 增加 `TuyaAppKey` / `TuyaAppSecret`；
   - 或直接改 `App/AppDelegate.swift` 与 `Common/TuyaConfig.swift` 里的常量（**勿提交到公开仓库**）。
5. 包名 / Bundle ID 必须为 `com.ipc.test.set`，与 IoT 平台一致。
6. **真机调试**（iPhone，ARM64）。模拟器需 Rosetta，且 P2P 体验不完整，建议真机。
7. 运行 Debug，启动页为 **登录**；应用名显示为 **IPC Demo**。

---

## 2. 整体流程

```text
登录 / 注册
  → 控制台（主页面）
      ├─ 创建 / 选择家庭
      ├─ EZ / AP / 摄像头二维码 配网
      └─ 设备列表 → 点击摄像机
            → 实时预览面板
                ├─ 预览控制：对讲 / 截图 / 录像 / 静音 / 清晰度 / 视频通话*
                ├─ 双指缩放 / 双击放大 · 横屏全屏
                ├─ 设备功能：云台* · 存储卡 · 卡录像 · 本地相册 · 消息
                └─ 云存储* / 增值服务*（仅支持云存储时显示）
```

`*` 表示按设备能力显隐。

---

## 3. 界面总览（UI 示例）

配色：背景 `#EEF2F5`，顶栏 `#1B2E3A`，主色 `#1F6F8B`，强调色 `#D97706`（与 Android 一致，见 `TuyaConfig.swift`）。

### 3.1 登录页

类：`Account/LoginViewController.swift`

```text
┌─────────────────────────────────────┐
│ ████  (顶栏深色)                      │
│ IPC Demo                             │
│ Smart Life · IPC 演示                 │
├─────────────────────────────────────┤
│  ┌─ 白底卡片 ─────────────────────┐  │
│  │ 账号                            │  │
│  │ [国家码 86      ]                │  │
│  │ [账号（手机/邮箱）]              │  │
│  │ [密码           ]                │  │
│  │ [        登 录        ]           │  │
│  │     去注册 →                     │  │
│  └─────────────────────────────────┘  │
└─────────────────────────────────────┘
```

| 步骤 | 操作 |
|------|------|
| 登录 | 国家码 + 账号 + 密码 → **登录** |
| 注册 | 进入注册页 → 获取验证码 → 完成注册 |
| 已登录 | 再次打开直接进控制台（`AppDelegate.routeToRoot`） |

---

### 3.2 主页面（控制台）★

类：`Home/MainViewController.swift`

```text
┌─────────────────────────────────────┐
│ ████                                 │
│ IPC Demo                             │
│ 家庭 · 配网 · 设备准备                 │
├─────────────────────────────────────┤
│  ┌─ 家庭卡片 ─────────────────────┐  │
│  │ 当前：我的家                     │  │
│  │ ───────────────────────────     │  │
│  │ 家庭列表                        │  │
│  └─────────────────────────────────┘  │
│  ┌─ 操作卡片 ─────────────────────┐  │
│  │ [      创建家庭      ]             │  │
│  │ [      家庭列表      ]           │  │
│  │ [    刷新家庭列表    ]           │  │
│  │ [      EZ 配网       ]           │  │
│  │ [      AP 配网       ]           │  │
│  │ [  摄像头二维码配网  ]           │  │
│  │ [      设备列表      ]           │  │
│  │ [      离线日志      ]           │  │
│  │ [      退出登录      ]           │  │
│  └─────────────────────────────────┘  │
└─────────────────────────────────────┘
```

| 按钮 | 作用 |
|------|------|
| 创建家庭 | 创建后作为当前家庭 |
| 家庭列表 | 切换当前家庭 |
| 刷新家庭列表 | 重新拉取家庭数据 |
| EZ / AP / 摄像头二维码配网 | 三种配网方式 |
| 设备列表 | 当前家庭设备（需已选家庭） |
| 离线日志 | 导出 SDK 日志（`OfflineLogViewController`）；见 [离线日志集成文档](./IPC_离线日志集成文档.md) |
| 退出登录 | 回登录页 |

---

### 3.3 设备列表

类：`Home/DeviceListViewController.swift`

| 操作 | 说明 |
|------|------|
| 点击 IPC | 进入实时预览 |
| 点击非 IPC | 提示无法打开预览 |
| **长按** | 确认后从家庭移除设备 |

---

### 3.4 实时预览面板（核心）

类：`IPC/CameraPanelViewController.swift`，能力封装见 `IPC/CameraController.swift`（`CameraController` + `CameraSessionManager`）。

当前布局（2026-10-22 版）：

```text
┌─────────────────────────────────────┐
│ ←  实时预览                    [全屏] │
├─────────────────────────────────────┤
│ ┌─ 预览区（屏幕上半部分）─────────┐  │
│ │ 预览中                             │  │
│ │         （视频画面）               │  │
│ │                双指缩放 / 双击放大 │  │
│ └───────────────────────────────────┘ │
├─────────────────────────────────────┤
│ 控制区（屏幕下方，深色背景）          │
│  [↑][↓][←][→] 云台方向键             │
│  [全屏][更多][声音][对讲]             │
│  [截图][录像][高清]                   │
└─────────────────────────────────────┘
```

> 说明：预览固定在**屏幕上半部分**，云台方向键与全部功能按钮**统一固定在下方控制区**（不再浮在画面中央）。点「全屏」后隐藏底部控制区、预览铺满并呈横屏观感（不影响设备方向，规避 iOS 26 私有 API 断言）。

#### 预览手势

| 手势 | 效果 |
|------|------|
| 双指捏合 | 视觉缩放约 1×～4×（`CameraController.zoom`） |
| 双击画面 | 放大 / 还原（`ThingSmartCameraType` 默认支持双击缩放） |

#### 预览控制

| 按钮 | 说明 |
|------|------|
| 声音（静音 / 开启） | 预览音频；切声音前会预设 `AVAudioSession(.playAndRecord + .defaultToSpeaker)` |
| 高清 / 标清 | 清晰度（`setDefinition(.high/.standard)`） |
| 对讲 | 需麦克风权限（`startAudioTalk`） |
| 截图 | 存至 App 沙盒私有目录；可去「本地相册」查看 |
| 录像 | 本地 MP4；停止后可在「本地相册」查看 |
| 全屏 | 横屏全屏预览 |

截图/录像路径（App 沙盒，系统文件管理器默认看不到）：

```text
<App Container>/Documents/<设备ID>/    # 由 IpcLocalMediaHelper 管理
```

#### 设备功能入口

| 入口 | 说明 | 显示条件 |
|------|------|----------|
| 云台 | 上/下/左/右 | 支持 PTZ DP（`ThingSmartPTZManager`） |
| 存储卡 | 状态、格式化、卡录像开关等 | 有相关 DP |
| 卡录像 | SD 回放 + 时间轴 | 常显 |
| 本地相册 | 截图/本地录像浏览 | 常显 |
| 消息 | 当天告警消息 | 常显 |
| 云存储 / 增值服务 | 云录像 / VAS | 设备支持云存储时显示 |

#### 横屏全屏

- 顶栏与竖屏功能区隐藏；左上角返回退出全屏。
- 底部操作条：静音 / 清晰度 / 对讲 / 截图 / 录像。
- 方向由 `AppDelegate.supportedInterfaceOrientationsFor` 转交给当前最上层 VC，预览页在全屏时返回 `.landscape`。

---

### 3.5 摄像头二维码配网

类：`Config/QrConfigViewController.swift`

1. 主页面 → **摄像头二维码配网**（需已选家庭）。
2. 填写 2.4GHz Wi-Fi → 生成二维码。
3. 二维码正对摄像机（约 15–20cm）扫描。
4. 成功后到设备列表查看。

---

### 3.6 本地相册

类：`IPC/CameraAlbumViewController.swift`

- 网格展示本设备 jpg / mp4；点击可全屏看图或播录像。
- 页顶显示保存目录路径。

---

## 4. EZ / AP 配网

### EZ

主页面 → EZ 配网 → 填 Wi-Fi → 设备进配网模式 → 开始配网（`Config/EzConfigViewController.swift`）。

### AP

主页面 → AP 配网 → 填路由 Wi-Fi → 连接设备热点（如 `SmartLife-XXXX`）→ 回 App 激活（`Config/ApConfigViewController.swift`）。

---

## 5. 存储卡 / 卡录像 / 消息 / 云存储

| 功能 | 路径 | 说明 |
|------|------|------|
| 存储卡 | 预览 → 存储卡 | 状态、容量、格式化、卡录像开关、水印（`CameraSdManageViewController`） |
| 卡录像 | 预览 → 卡录像 | 进页前释放预览 P2P；时间轴播放；时间轴刷新约每 400ms（`CameraPlaybackViewController`，间隔见 `TuyaConfig.timelineRefreshInterval`） |
| 消息 | 预览 → 消息 | schema 有 `motion_switch` 才显示开关；当天告警（`CameraMessageViewController` / `CameraVideoMessageViewController`） |
| 云存储 / VAS | 预览对应入口 | 仅支持云存储的设备可见（`CameraCloudStorageViewController`） |

> 卡回放常见错误码与 Android 一致：`-40201`（会话/参数）、`-40205`（该点无录像）。

---

## 6. 门铃呼叫

设备支持时，来电拉起接听 / 拒接 / 挂断界面（`CameraDoorBellViewController.swift` + `DoorbellCallManager.swift`）。

---

## 7. 推荐验收清单

- [ ] 登录并创建/选择家庭  
- [ ] EZ / AP / 二维码配网至少一种成功  
- [ ] 设备列表可见；长按可移除  
- [ ] IPC 预览有画面；双指缩放、双击放大  
- [ ] 声音、清晰度、对讲（注意：首次进预览/切声音需先预设 AVAudioSession，否则会出现「已停止预览」反复重连）  
- [ ] 截图、本地录像 → 本地相册可查看  
- [ ] 横屏全屏可用  
- [ ] 不支持云存储则看不到云入口  
- [ ] 卡录像 / 消息可打开  

---

## 8. 操作注意

1. 预览依赖公网与 P2P。  
2. 对讲需麦克风；配网常需定位 / 本地网络权限。  
3. 进卡录像/云存储前 Demo 会释放预览连接（通过 `CameraSessionManager` 引用计数）。  
4. 截图在 App 沙盒私有目录，不在系统相册。  
5. Bundle ID、AppKey、AppSecret 须与 IoT 平台一致。  
6. **iOS 专项**：若预览反复提示「已停止预览」，通常是 `AVAudioSession` 未预设 `playAndRecord` 导致 SDK 音频初始化失败、P2P 反复重连。进页面与切声音/对讲前先 `setCategory(.playAndRecord, options:[.defaultToSpeaker, .mixWithOthers])` 即可稳定（详见集成文档）。  
7. **iOS 专项**：必须用 `.xcworkspace` 打开；安全 SDK `Build/` 切勿提交到公开仓库。

---

## 9. 界面与代码对照

| 界面 | 类 / 文件 |
|------|-----------|
| 登录 | `Account/LoginViewController.swift` |
| 注册 | `Account/RegisterViewController.swift` |
| 主页面 | `Home/MainViewController.swift` |
| 二维码配网 | `Config/QrConfigViewController.swift` |
| EZ / AP 配网 | `Config/EzConfigViewController.swift` / `Config/ApConfigViewController.swift` |
| 设备列表 | `Home/DeviceListViewController.swift` |
| 实时预览 | `IPC/CameraPanelViewController.swift` + `IPC/CameraController.swift` |
| 本地相册 | `IPC/CameraAlbumViewController.swift` |
| 卡录像 | `IPC/CameraPlaybackViewController.swift` |
| 存储卡 | `IPC/CameraSdManageViewController.swift` |
| 云存储 | `IPC/CameraCloudStorageViewController.swift` |
| 消息 | `IPC/CameraMessageViewController.swift` / `CameraVideoMessageViewController.swift` |
| 门铃 | `IPC/CameraDoorBellViewController.swift` / `DoorbellCallManager.swift` |
| 离线日志 | `IPC/OfflineLogViewController.swift` |
| 预览能力封装 | `IPC/CameraController.swift`（`CameraController` + `CameraSessionManager`） |

更完整的 API 见 [集成文档](./IPC_SDK_集成文档.md)。
