# IPC Demo (iOS) — 涂鸦智能生活 App SDK 5.0 (ThingSmart) + 摄像机 IPC SDK
#
# ⚠️ 5.0 安全 SDK（ThingSmartCryption）必读：
#   1. 前往涂鸦开发者平台 https://platform.tuya.com/oem/sdkList
#      选择你的 App → 构建并下载「iOS 版本 SDK」(ios_core_sdk.tar.gz)。
#   2. 解压后得到：
#        - ThingSmartCryption.podspec
#        - Build/（App 专属安全 SDK，与 App 密钥同等重要，切勿外泄）
#   3. 把这两个文件/目录放在本 Podfile 同级目录（即 IPC_Demo_iOS/ 下）。
#   4. 再执行 `pod install`。
#
# 集成步骤：
#   cd IPC_Demo_iOS
#   xcodegen generate   # 生成 .xcodeproj
#   pod install          # 生成 .xcworkspace，之后用 .xcworkspace 打开

# ⚠️ source 缺一不可（参照官方 demo tuya-home-ios-sdk-sample-objc）：
#   - CocoaPods 官方 CDN 源：YYModel / SVProgressHUD 等第三方库在这里
#   - 涂鸦公共 + 私有 spec 仓库：ThingSmart* 系列在这里
#   声明了 source 后 CocoaPods 只在列出的源里查找，漏了就会报
#   "Unable to find a specification for `YYModel`"。
source 'https://cdn.cocoapods.org/'
source 'https://github.com/tuya/TuyaPublicSpecs.git'
source 'https://github.com/tuya/tuya-pod-specs.git'

platform :ios, '11.0'
use_frameworks!

target 'IPC_Demo_iOS' do
  # 5.0 安全 SDK（:path 指向 Podfile 同级解压目录，与官方 demo 一致）
  pod "ThingSmartCryption", :path => './'

  # 智能生活 App SDK：账号 / 家庭 / 配网 / 设备管理（版本与官方 demo 对齐）
  pod "ThingSmartHomeKit", '~> 7.8.0'

  # 摄像机（IPC）SDK：预览 / 回放 / 云存储 / 门铃
  pod "ThingSmartCameraKit"

  # 可选：业务拓展包，封装了更多便捷能力（本 Demo 未使用，按需开启）
  # pod "ThingSmartBusinessExtensionKit"
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['CLANG_WARN_DOCUMENTATION_COMMENTS'] = 'NO'
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '11.0'
      # M 系列芯片上模拟器需要 Rosetta（安全 SDK 无模拟器 arm64 切片）
      config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
    end
  end
end
