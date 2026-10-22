# IPC Demo (iOS)

涂鸦 **Smart Life App SDK 5.0 + 摄像机 IPC SDK** 演示工程（Swift 5，Bundle ID `com.ipc.test.set`）。

面向开发者的统一入口：克隆本仓库 → 按下方步骤跑通 Demo → 对照文档集成到自有 App。

## 文档入口

| 文档 | 说明 |
|------|------|
| [操作文档](docs/IPC_Demo_操作文档.md) | 主页面等 UI 线框、登录/配网（含二维码）、预览/相册/横屏、验收清单 |
| [集成文档](docs/IPC_SDK_集成文档.md) | CocoaPods 依赖、初始化、预览/音频会话/云台/回放 API 与代码映射 |
| [离线日志集成](docs/IPC_离线日志集成文档.md) | 日志落盘目录、系统分享导出、易错点 |
| [5.0 SDK 指南](README-zh.md) / [English](README-en.md) | 涂鸦 5.0 安全 SDK 集成说明（官方） |

## 环境要求

- Xcode 15+（含命令行工具）
- [xcodegen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）
- CocoaPods 1.12+
- 真机（ARM64，建议 iPhone）；模拟器需 Rosetta
- [涂鸦 IoT 平台](https://iot.tuya.com/) 账号与已创建 App
- 5.0 安全 SDK `ios_core_sdk.tar.gz`（平台下载，解压出 `Build/` 与 `ThingSmartCryption.podspec`）

## 快速开始

1. **克隆仓库**
   ```bash
   git clone <your-repo-url> IPC_Demo_iOS
   cd IPC_Demo_iOS
   ```

2. **放置 5.0 安全 SDK（勿提交）**
   解压 `ios_core_sdk.tar.gz`，把 `Build/` 与 `ThingSmartCryption.podspec` 放到 `Podfile` 同级目录（即仓库根）。

3. **生成工程并安装依赖**
   ```bash
   xcodegen generate     # 由 project.yml 生成 .xcodeproj
   pod install           # 生成 .xcworkspace
   ```

4. **配置密钥（勿提交明文）**
   在 `Info.plist` 增加键 `TuyaAppKey` / `TuyaAppSecret`，或改 `App/AppDelegate.swift`、`Common/TuyaConfig.swift` 里的常量。Bundle ID 须为 `com.ipc.test.set`，与 IoT 平台一致。

5. **运行**
   用 **`IPC_Demo_iOS.xcworkspace`** 打开（不是 `.xcodeproj`）→ 真机 Debug 运行 → 按 [操作文档](docs/IPC_Demo_操作文档.md) 体验。

## 功能一览

- 账号登录 / 注册、家庭管理
- EZ / AP / **摄像头二维码** 配网
- IPC 实时预览、双指缩放、双击放大、对讲、截图、录像、清晰度、视频通话（能力门控）
- 横屏全屏预览（容器 transform 旋转，不调设备方向）
- **本地相册**（截图 / 本地录像浏览）
- 云台、存储卡、卡录像时间轴、消息中心
- 云存储 / 增值服务（仅设备支持时展示）
- 设备列表长按移除
- 门铃来电（设备支持时）
- **离线日志**（导出沙盒 `Cache/com.tuya.smart/log`，系统分享）

## 版本

| 组件 | 版本 |
|------|------|
| ThingSmartHomeKit | ~> 7.8.0 |
| ThingSmartCameraKit | 最新（对齐 Android ipcsdk 7.8.1） |
| ThingSmartCryption | 5.0 安全 SDK（平台构建） |

详见 `Podfile` / `project.yml`。

## 安全说明

- 不要把 AppKey、AppSecret、签名密码写入仓库或截图。
- 安全 SDK `Build/` 与 `ThingSmartCryption` 内的密钥文件**严禁外泄**，已在 `.gitignore` 排除。
- 公开分享前请确认 `Info.plist` / 代码中无硬编码密钥。
- 内部交付摘要 `docs/IPC_Demo_内部交付文档.md` **不上传 GitHub**（仅内部传阅）。
