import UIKit
import AVFoundation
import ThingSmartCameraKit
import ThingSmartCameraBase

/// ┌──────────────────────────────────────────────────────────────────────┐
/// │ 相机能力统一封装（对应 Android IThingSmartCameraP2P / ThingCameraView）。│
/// │ 所有涂鸦摄像机 SDK 调用都集中在此文件，便于按安装版本微调方法名。       │
/// │                                                                        │
/// │ 已对齐涂鸦 iOS SDK 5.x（ThingSmart）真实头文件：                        │
/// │   · 创建：ThingSmartCameraFactory.createCamera(withDeviceId:delegate:) │
/// │   · 类型：ThingSmartCameraType 协议（int 返回值 + delegate 回调）        │
/// │   · 云台：ThingSmartPTZManager（startPTZWithDirection / stopPTZ）       │
/// │                                                                        │
/// │ 会话生命周期约定（本次优化重点）：                                       │
/// │   · 会话不要由页面各自 new，统一由 CameraSessionManager 按 devId 复用；   │
/// │   · connect() 幂等，重复 viewDidAppear 不会再开一条 P2P 通道；           │
/// │   · teardown() 是唯一的释放入口：停流→断连→摘渲染视图→丢 camera 对象。   │
/// └──────────────────────────────────────────────────────────────────────┘

@objc protocol CameraControllerDelegate: AnyObject {
    @objc optional func cameraDidConnect(_ c: CameraController)
    @objc optional func cameraDidFailConnect(_ c: CameraController, error: Error?)
    @objc optional func cameraDidStartPreview(_ c: CameraController)
    @objc optional func cameraDidStopPreview(_ c: CameraController)
    @objc optional func cameraSnapshotSaved(_ c: CameraController, success: Bool)
    @objc optional func cameraRecordingChanged(_ c: CameraController, recording: Bool)
    @objc optional func cameraMuteChanged(_ c: CameraController, muted: Bool)
    @objc optional func cameraTalkChanged(_ c: CameraController, talking: Bool)
    /// 长会话体检做出的自适应（自动降清晰度 / 重新起播），message 可直接提示用户
    @objc optional func cameraQualityAdjusted(_ c: CameraController, message: String)
    // 回放（SD 卡）
    @objc optional func cameraDidStartPlayback(_ c: CameraController)
    @objc optional func cameraDidStopPlayback(_ c: CameraController)
    @objc optional func cameraPlaybackProgress(_ c: CameraController,
                                               playTime: TimeInterval,
                                               fileStart: TimeInterval,
                                               fileEnd: TimeInterval,
                                               status: Int)
    @objc optional func cameraDidError(_ c: CameraController, error: Error?)
}

final class CameraController: NSObject {

    /// 活跃会话计数：用于验收「离开页面后是否真的释放」。进出预览 N 次后应回到 0。
    private(set) static var liveSessionCount = 0

    let devId: String

    /// 多播回调：同一 devId 的会话可被预览页/回放页/门铃共同挂载，
    /// 全部为 weak 引用，页面销毁后自动掉出列表，不会互相拖住释放。
    private let handlers = NSHashTable<CameraControllerDelegate>.weakObjects()
    func addHandler(_ handler: CameraControllerDelegate) {
        if !handlers.contains(handler) { handlers.add(handler) }
    }
    func removeHandler(_ handler: CameraControllerDelegate) { handlers.remove(handler) }
    private func forEachDelegate(_ body: (CameraControllerDelegate) -> Void) {
        handlers.allObjects.forEach(body)
    }

    /// 涂鸦相机对象（ThingSmartCameraType 协议）
    private(set) var camera: (any ThingSmartCameraType)?
    /// 预览渲染视图：必须在 cameraDidBeginPreview 时由 SDK 的 videoView() 取得，
    /// 并 add 到界面。改自计算属性为单一存储属性，避免多次调用 videoView() 产生不同实例导致"已连接但黑屏"。
    private(set) var previewView: UIView?

    /// 云台管理器（对应 Android PTZ）
    private lazy var ptzManager = ThingSmartPTZManager(deviceId: devId)

    private(set) var isPreviewing = false
    private(set) var isConnected = false
    /// 已彻底释放：置位后拒绝再次 connect，避免释放途中被异步回调复活
    private(set) var isReleased = false
    private var firstFrameReceived = false
    private var diagnosticPrinted = false
    private(set) var isRecording = false
    private(set) var isTalking = false
    private(set) var isMuted = true
    /// 清晰度：true=高清，false=标清（对应 Android HD/STANDEND）
    var isHD = true

    /// 回放查询回调（SDK 通过 delegate 返回结果）
    private var recordDaysHandler: (([Int]?, Error?) -> Void)?
    private var recordSlicesHandler: (([[String: Any]]?, Error?) -> Void)?

    init(devId: String) {
        self.devId = devId
        super.init()
        // 5.x 工厂方法：cameraWithP2PType:deviceId:delegate:
        // p2pType 必须取自设备 ThingSmartDeviceModel 的 p2pType 字段
        // （官方头注释明确要求：pass the "p2pType" field in the "skills" attribute）。
        // 1=TUTK 2=PPCS 3=THING。硬编码 3 会导致非 THING 设备连错 P2P 栈而拉不到流。
        let p2pType = Self.resolveP2PType(devId) ?? 3
        #if DEBUG
        print("[CameraController] devId=\(devId) 解析到 p2pType=\(p2pType)")
        #endif
        camera = ThingSmartCameraFactory.camera(withP2PType: p2pType, deviceId: devId, delegate: self)
        // ⚠️ 默认关闭 SDK 调试日志：开启后 SDK 会对每一帧音视频包打印 PushVideoPacket/PushAudioPacket，
        // 每秒数百条同步日志会占满主线程，导致「预览卡顿 + 按钮点不动」。
        // 需要排查拉流/解码问题时，把下面这行临时改为 true 即可。
        ThingSmartCameraSDK.sharedInstance.debugMode = false
        Self.liveSessionCount += 1
        #if DEBUG
        print("[Camera] 新建会话 devId=\(devId) 活跃会话=\(Self.liveSessionCount)")
        #endif
    }

    deinit { teardown() }

    /// 从设备模型读取真实 p2pType；读不到时返回 nil，由调用方兜底为 3。
    private static func resolveP2PType(_ devId: String) -> Int? {
        guard let model = ThingSmartDevice(deviceId: devId)?.deviceModel else { return nil }
        let t = model.p2pType()
        return t > 0 ? t : nil
    }

    /// 取得 SDK 视频渲染视图（单一实例）。提前挂到界面可确保解码图层在收到首帧前已就绪。
    func cameraVideoView() -> UIView? {
        if previewView == nil { previewView = camera?.videoView() }
        return previewView
    }

    // MARK: - 连接 / 预览
    func connect() {
        // 幂等：已连接或已释放时不再发起，避免对同一 camera 对象重复建会话。
        // （历史上 viewDidAppear 每次都 connect 是「多次进出后卡死」的直接来源）
        guard camera != nil, !isReleased, !isConnected else { return }
        // 文档推荐 connectWithMode:(auto)：自动选择局域网/外网（PPCS 设备务必用此模式，
        // 否则可能连上但不推送视频帧）。connectWithMode 在协议 @optional 段，需可选链调用。
        camera?.connect?(with: .auto)
        // 连接结果通过 delegate：cameraDidConnected / didOccurredErrorAtStep
    }

    func startPreview() {
        guard camera != nil, !isReleased else { return }
        _ = camera?.startPreview()
    }

    func stopPreview() { _ = camera?.stopPreview() }

    /// 只断通道、保留 camera 对象：用于退到后台等「稍后还要用」的场景
    func disconnect() {
        guard camera != nil else { return }
        isConnected = false
        isPreviewing = false
        _ = camera?.disConnect()
    }

    /// 退出页面时彻底释放（对应 Android destroyP2P）。
    /// 顺序不能乱：先停业务通道，再断 P2P，最后摘渲染视图，否则 GL 图层会残留在层级里。
    func teardown() {
        guard !isReleased else { return }
        isReleased = true
        stopHealthWatch()
        if isTalking { _ = camera?.stopAudioTalk() }
        if isRecording { _ = camera?.stopRecord() }
        _ = camera?.stopPreview()
        isConnected = false
        isPreviewing = false
        // 显式让 SDK 松开渲染视图：只 removeFromSuperview 的话 SDK 内部仍强引用着它，
        // GL 上下文会随会话一起留着，多次进出后越来越重。
        if let cam = camera, let pv = previewView as? (UIView & ThingSmartVideoViewType) {
            cam.uninstallVideoRenderView?(pv)
        }
        _ = camera?.disConnect()
        camera = nil
        detachRenderView()
        handlers.removeAllObjects()
        recordDaysHandler = nil
        recordSlicesHandler = nil
        Self.liveSessionCount = max(0, Self.liveSessionCount - 1)
        #if DEBUG
        print("[Camera] 释放会话 devId=\(devId) 活跃会话=\(Self.liveSessionCount)")
        #endif
    }

    /// 把 SDK 渲染视图从父视图摘掉并丢弃缓存实例，下次 acquire 会重新向 SDK 取
    func detachRenderView() {
        guard let view = previewView else { return }
        previewView = nil
        // deinit 路径可能在非主线程触发，UIKit 操作必须回主线程
        if Thread.isMainThread {
            view.removeFromSuperview()
        } else {
            DispatchQueue.main.async { view.removeFromSuperview() }
        }
    }

    /// 预览开始 2 秒后诊断：区分「没收到帧」(流/设备问题) 与「收到帧但没画出来」(渲染视图问题)
    private func dumpRenderDiagnostics() {
        #if DEBUG
        guard !diagnosticPrinted else { return }
        diagnosticPrinted = true
        guard let cam = camera else { return }
        let w = cam.getCurViewWidth()
        let h = cam.getCurViewHeight()
        let pv = previewView
        print("[Camera][诊断] 解码尺寸 w=\(w) h=\(h) | 是否收到首帧=\(firstFrameReceived) | renderView.superview=\(pv?.superview ?? nil) | renderView.window=\(pv?.window ?? nil) | renderView.frame=\(pv?.frame ?? .zero)")
        if !firstFrameReceived {
            print("[Camera][诊断] ⚠️ 2 秒内未收到任何解码帧 → 问题在\"流/设备\"层（设备被其它端占用、p2pType 不匹配、局域网穿透失败），不是渲染层问题")
        } else if pv?.superview == nil || pv?.window == nil {
            print("[Camera][诊断] ⚠️ 已收到帧，但渲染视图不在屏幕上 → 渲染视图挂载时机/层级问题")
        } else {
            print("[Camera][诊断] ✅ 已收到帧且渲染视图在屏幕上；若仍黑屏多为 OpenGL 图层尺寸为 0，需强制 layout")
        }
        #endif
    }

    // MARK: - 截图 / 录像
    func snapshot() {
        // snapShoot() 返回当前帧；编码与落盘全部转到 ioQueue，
        // 免得在 SDK 回调线程做 JPEG 编码造成预览瞬间掉帧
        guard let img = camera?.snapShoot() else {
            DispatchQueue.main.async { self.forEachDelegate { $0.cameraSnapshotSaved?(self, success: false) } }
            return
        }
        IpcLocalMediaHelper.ioQueue.async {
            IpcLocalMediaHelper.saveImage(img, devId: self.devId)
            DispatchQueue.main.async { self.forEachDelegate { $0.cameraSnapshotSaved?(self, success: true) } }
        }
    }

    func startRecord(to path: String) {
        // startRecordWithFilePath: 位于协议 @optional 段，存在体调用需用 ? 解包
        if let cam = camera {
            _ = cam.startRecord?(withFilePath: path)
        }
        isRecording = true
        DispatchQueue.main.async { self.forEachDelegate { $0.cameraRecordingChanged?(self, recording: true) } }
    }

    func stopRecord() {
        _ = camera?.stopRecord()
        isRecording = false
        DispatchQueue.main.async { self.forEachDelegate { $0.cameraRecordingChanged?(self, recording: false) } }
    }

    // MARK: - 静音 / 清晰度 / 对讲
    func setMuted(_ muted: Bool) {
        _ = camera?.enableMute(muted, for: .preview)
        // 实际结果通过 delegate `didReceiveMuteState` 回调
    }

    func setHD(_ hd: Bool) {
        isHD = hd
        _ = camera?.setDefinition(hd ? .high : .standard)
    }

    func startTalk() {
        _ = camera?.startAudioTalk()
    }

    func stopTalk() {
        _ = camera?.stopAudioTalk()
    }

    // MARK: - 云台（对应 Android PTZ）
    func startPTZ(_ direction: ThingSmartPTZControlDirection) {
        ptzManager.startPTZ(with: direction, success: { _ in }, failure: { [weak self] error in
            if let error = error {
                DispatchQueue.main.async { self?.forEachDelegate { $0.cameraDidError?(self!, error: error) } }
            }
        })
    }

    func stopPTZ() {
        ptzManager.stopPTZ(success: { _ in }, failure: { _ in })
    }

    /// 数字变倍（双指捏合 / 双击放大，对应 Android 缩放）。
    /// 实现方式：对预览视图做视觉缩放。
    func zoom(_ scale: CGFloat) {
        let s = max(1.0, min(scale, 4.0))
        previewView?.transform = CGAffineTransform(scaleX: s, y: s)
    }

    // MARK: - 回放（SD 卡）
    func queryRecordDays(year: Int, month: Int, completion: @escaping ([Int]?, Error?) -> Void) {
        recordDaysHandler = completion
        camera?.queryRecordDays(withYear: UInt(max(0, year)), month: UInt(max(1, min(12, month))))
    }

    func queryRecordTimeSlices(date: Date, completion: @escaping ([[String: Any]]?, Error?) -> Void) {
        recordSlicesHandler = completion
        let c = Calendar.current
        let comps = c.dateComponents([.year, .month, .day], from: date)
        camera?.queryRecordTimeSlice(withYear: UInt(comps.year ?? 2024),
                                     month: UInt(comps.month ?? 1),
                                     day: UInt(comps.day ?? 1))
    }

    /// 从指定时刻开始回放当天录像
    func startPlayback(date: Date) {
        camera?.enterPlayback()
        let start = Calendar.current.startOfDay(for: date)
        let seconds = Int(date.timeIntervalSince(start))
        _ = camera?.startPlayback(seconds, startTime: 0, stopTime: 86_400)
    }

    func stopPlayback() { _ = camera?.stopPlayback() }
    func pausePlayback() { _ = camera?.pausePlayback() }
    func resumePlayback() { _ = camera?.resumePlayback() }

    /// 拖动进度条：重新从目标时间点起播
    func seekPlayback(time: TimeInterval) {
        _ = camera?.startPlayback(Int(time), startTime: 0, stopTime: 86_400)
    }

    func mutePlayback(_ muted: Bool) {
        _ = camera?.enableMute(muted, for: .playback)
    }

    // MARK: - 长时间预览的卡顿体检
    // 逐帧回调只记账、不做任何分配；判断集中在每 5 秒一次的体检里，
    // 因为「越看越卡」的表现是码率/缓冲随时间劣化，单次采样看不出来。
    private static let healthWindow: TimeInterval = 5
    private let statsLock = NSLock()
    private var frameCount = 0
    private var stallCount = 0
    private var deviceFps = 0
    private var lastFrameAt: CFTimeInterval = 0
    private var lastFlushAt: CFTimeInterval = 0
    private var badWindows = 0
    private var healthTimer: Timer?

    private func startHealthWatch() {
        guard healthTimer == nil else { return }
        let t = Timer(timeInterval: Self.healthWindow, repeats: true) { [weak self] _ in
            self?.evaluatePreviewHealth()
        }
        // .common：滚动/转场期间也要照常体检
        RunLoop.main.add(t, forMode: .common)
        healthTimer = t
    }

    private func stopHealthWatch() {
        let timer = healthTimer
        healthTimer = nil
        guard let timer = timer else { return }
        // invalidate 必须在定时器所在线程执行；teardown 可能来自 deinit（非主线程）
        if Thread.isMainThread { timer.invalidate() }
        else { DispatchQueue.main.async { timer.invalidate() } }
    }

    private func resetFrameStats() {
        statsLock.lock()
        frameCount = 0; stallCount = 0; lastFrameAt = 0; badWindows = 0
        statsLock.unlock()
    }

    private func recordVideoFrame(reportedFps: Int) {
        let now = CACurrentMediaTime()
        statsLock.lock()
        frameCount += 1
        // 帧间隔大于 400ms 记一次卡帧：这是纯本地时钟，不依赖设备时间戳单位
        if lastFrameAt > 0, now - lastFrameAt > 0.4 { stallCount += 1 }
        lastFrameAt = now
        deviceFps = reportedFps
        statsLock.unlock()
    }

    private func takeFrameSample() -> (fps: Double, stalls: Int, reportedFps: Int) {
        statsLock.lock()
        let f = frameCount, s = stallCount, r = deviceFps
        frameCount = 0; stallCount = 0
        statsLock.unlock()
        return (Double(f) / Self.healthWindow, s, r)
    }

    private func evaluatePreviewHealth() {
        guard !isReleased, isPreviewing, let cam = camera else { return }
        let sample = takeFrameSample()
        // 逐帧回调若没接上，fps 恒为 0：此时直接退出，不能据此降级（会误判）
        guard sample.fps > 0 else {
            #if DEBUG
            print("[Camera][体检] 未收到逐帧回调，体检暂停（fps=0）")
            #endif
            return
        }
        let kbps = cam.getVideoBitRateKBPS?() ?? 0
        let thermal = ProcessInfo.processInfo.thermalState
        #if DEBUG
        print(String(format: "[Camera][体检] fps=%.1f 设备上报=%d 卡帧=%d 码率=%.0fKbps 清晰度=%@ 温控=%@",
                     sample.fps, sample.reportedFps, sample.stalls, kbps, isHD ? "高清" : "标清",
                     thermal == .nominal ? "正常" : (thermal == .fair ? "偏热" : (thermal == .serious ? "严重" : "危险"))))
        #endif

        // 长时间停留在预览最容易先触发温控降频：CPU/GPU 一降，高清硬解就追不上帧。
        // 这种情况不用等卡够 10 秒，直接降码流。
        if (thermal == .serious || thermal == .critical), isHD {
            setHD(false)
            notifyQuality("机身温控降频中，已自动切到标清")
            return
        }

        // 连续两个窗口（约 10 秒）才动手，瞬时抖动不处理
        if sample.fps < 10 || sample.stalls >= 4 { badWindows += 1 } else { badWindows = 0 }
        guard badWindows >= 2 else { return }
        badWindows = 0

        if isHD {
            setHD(false)
            notifyQuality("下行带宽不足，已自动切到标清")
            return
        }

        // 已经是标清还在卡：多半是解码/渲染队列积压，重起一次播把缓冲清掉
        let now = CACurrentMediaTime()
        guard now - lastFlushAt > 30 else { return }
        lastFlushAt = now
        notifyQuality("画面缓冲积压，正在重新起播")
        _ = cam.stopPreview()
        // 弱引用 + 释放判断：页面可能在这 0.4 秒里被销毁
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self = self, !self.isReleased else { return }
            _ = self.camera?.startPreview()
        }
    }

    private func notifyQuality(_ message: String) {
        DispatchQueue.main.async { self.forEachDelegate { $0.cameraQualityAdjusted?(self, message: message) } }
    }
}

// MARK: - ThingSmartCameraDelegate（协议方法均为必选，无 @optional）
extension CameraController: ThingSmartCameraDelegate {

    // 连接生命周期
    func cameraInitFailed(_ errorCode: ThingSmartCameraErrorCode) {
        DispatchQueue.main.async {
            self.forEachDelegate {
                $0.cameraDidFailConnect?(self, error: NSError(domain: "CameraInit", code: Int(errorCode.rawValue)))
            }
        }
    }

    func cameraDidConnected(_ camera: ThingSmartCameraType!) {
        guard !isReleased else { return }
        isConnected = true
        #if DEBUG
        print("[Camera] cameraDidConnected ✅ P2P 通道已连接，准备 startPreview")
        // 预览诊断看门狗：无论 cameraDidBeginPreview 是否触发，6 秒后都输出一次渲染诊断，
        // 确保即使"已连接但不出帧"也能拿到 A/B 判定，不依赖 beginPreview 回调。
        // 必须弱捕获，否则每个定时器都会把会话对象拖住 6 秒，页面退出后无法及时释放。
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in self?.dumpRenderDiagnostics() }
        #endif
        DispatchQueue.main.async { self.forEachDelegate { $0.cameraDidConnect?(self) } }
    }

    func cameraDisconnected(_ camera: ThingSmartCameraType!, specificErrorCode errorCode: Int) {
        isConnected = false
        isPreviewing = false
        DispatchQueue.main.async { self.stopHealthWatch() }
        #if DEBUG
        if !isReleased { print("[Camera] ⚠️ 通道被对端/网络断开 code=\(errorCode) 活跃会话=\(Self.liveSessionCount)") }
        #endif
    }

    func cameraDidConnectPlaybackChannel(_ camera: ThingSmartCameraType!) { }

    // 预览
    func cameraDidBeginPreview(_ camera: ThingSmartCameraType!) {
        guard !isReleased else { return }
        // 按官方文档：在 cameraDidBeginPreview 回调里由 SDK 取得视频渲染视图（单一实例）
        if previewView == nil { previewView = camera?.videoView() }
        // 预览仍在进行却又收到 BeginPreview：说明 SDK 自己重起了码流（链路抖动的信号）
        let isRestart = isPreviewing
        isPreviewing = true
        DispatchQueue.main.async {
            self.resetFrameStats()
            self.startHealthWatch()
            if isRestart {
                #if DEBUG
                print("[Camera] ⚠️ SDK 重复触发 cameraDidBeginPreview：码流被自动重起，链路质量在抖动")
                #endif
            }
        }
        #if DEBUG
        if let pv = previewView {
            print("[Camera] cameraDidBeginPreview ✅ 渲染视图已就绪 class=\(type(of: pv)) frame=\(pv.frame) superview=\(pv.superview ?? nil)")
        } else {
            print("[Camera] ⚠️ cameraDidBeginPreview 已触发，但 videoView 返回 nil！")
        }
        print("[Camera] autoRender=\(camera?.autoRender ?? false)")
        #endif
        DispatchQueue.main.async {
            self.forEachDelegate { $0.cameraDidStartPreview?(self) }
            // 2 秒后做一次渲染诊断，确认是否有解码帧、渲染视图是否真正在屏幕上
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.dumpRenderDiagnostics() }
        }
    }

    func cameraDidStopPreview(_ camera: ThingSmartCameraType!) {
        isPreviewing = false
        DispatchQueue.main.async {
            self.stopHealthWatch()
            self.forEachDelegate { $0.cameraDidStopPreview?(self) }
        }
    }

    /// 逐帧回调：只做一次加锁计数，禁止在此打印/分配，否则本身就是卡顿来源。
    /// 显式钉住 selector，避免签名写错时静默不生效。
    @objc(camera:thing_didReceiveVideoFrame:frameInfo:)
    func camera(_ camera: ThingSmartCameraType!,
                thing_didReceiveVideoFrame sampleBuffer: CMSampleBuffer!,
                frameInfo: ThingSmartVideoFrameInfo) {
        recordVideoFrame(reportedFps: Int(frameInfo.nFrameRate))
    }

    // 回放生命周期
    func cameraDidBeginPlayback(_ camera: ThingSmartCameraType!) {
        DispatchQueue.main.async { self.forEachDelegate { $0.cameraDidStartPlayback?(self) } }
    }

    func cameraDidPausePlayback(_ camera: ThingSmartCameraType!) { }
    func cameraDidResumePlayback(_ camera: ThingSmartCameraType!) { }

    func cameraDidStopPlayback(_ camera: ThingSmartCameraType!) {
        DispatchQueue.main.async { self.forEachDelegate { $0.cameraDidStopPlayback?(self) } }
    }

    func cameraPlaybackDidFinished(_ camera: ThingSmartCameraType!) { }

    func camera(_ camera: ThingSmartCameraType!, playbackDidFinishedWith status: Int) { }

    func camera(_ camera: ThingSmartCameraType!, playbackTimeSlice timeSlice: [AnyHashable: Any]!, didFinishedWith status: Int) {
        guard let slice = timeSlice as? [String: Any] else { return }
        let playTime = (slice["playTime"] as? NSNumber)?.doubleValue ?? 0
        let fileStart = (slice["startTime"] as? NSNumber)?.doubleValue ?? 0
        let fileEnd = (slice["endTime"] as? NSNumber)?.doubleValue ?? 0
        DispatchQueue.main.async {
            self.forEachDelegate {
                $0.cameraPlaybackProgress?(self, playTime: playTime,
                                          fileStart: fileStart, fileEnd: fileEnd, status: status)
            }
        }
    }

    // 视频帧
    func camera(_ camera: ThingSmartCameraType!, didReceiveFirstFrame image: UIImage!) {
        firstFrameReceived = true
        #if DEBUG
        print("[Camera] 🎬 didReceiveFirstFrame 收到首帧 image=\(String(describing: image?.size))")
        #endif
    }
    func camera(_ camera: ThingSmartCameraType!, didReceiveFirstFrame image: UIImage!, videoExtInfo: Any!) {
        firstFrameReceived = true
        #if DEBUG
        print("[Camera] 🎬 didReceiveFirstFrame(videoExtInfo) 收到首帧 ✅")
        #endif
    }
    func camera(_ camera: ThingSmartCameraType!, didReceiveLocalVideoFirstFrame image: UIImage!, localVideoInfo: Any!) { }

    // 对讲
    func cameraDidBeginTalk(_ camera: ThingSmartCameraType!) {
        isTalking = true
        DispatchQueue.main.async { self.forEachDelegate { $0.cameraTalkChanged?(self, talking: true) } }
    }

    func cameraDidStopTalk(_ camera: ThingSmartCameraType!) {
        isTalking = false
        DispatchQueue.main.async { self.forEachDelegate { $0.cameraTalkChanged?(self, talking: false) } }
    }

    func cameraDidStartVideoTalk(_ camera: ThingSmartCameraType!) { }
    func cameraDidStopVideoTalk(_ camera: ThingSmartCameraType!) { }
    func cameraDidPauseVideoTalk(_ camera: ThingSmartCameraType!) { }
    func cameraDidResumeVideoTalk(_ camera: ThingSmartCameraType!) { }

    // 截图 / 录像状态
    func cameraSnapShootSuccess(_ camera: ThingSmartCameraType!) { }

    func cameraDidStartRecord(_ camera: ThingSmartCameraType!) {
        isRecording = true
        DispatchQueue.main.async { self.forEachDelegate { $0.cameraRecordingChanged?(self, recording: true) } }
    }

    func cameraDidStopRecord(_ camera: ThingSmartCameraType!) {
        isRecording = false
        DispatchQueue.main.async { self.forEachDelegate { $0.cameraRecordingChanged?(self, recording: false) } }
    }

    // 清晰度
    func camera(_ camera: ThingSmartCameraType!, definitionChanged definition: ThingSmartCameraDefinition) { }

    // 查询结果
    func camera(_ camera: ThingSmartCameraType!, didReceiveEventListSiftData titles: [String]!, eventIds: [NSNumber]!) { }

    func camera(_ camera: ThingSmartCameraType!, didReceiveRecordDayQueryData days: [NSNumber]!) {
        let list = days?.map { $0.intValue }
        let handler = recordDaysHandler
        recordDaysHandler = nil
        DispatchQueue.main.async { handler?(list, nil) }
    }

    func camera(_ camera: ThingSmartCameraType!, didReceiveTimeSliceQueryData timeSlices: [[AnyHashable: Any]]!) {
        let list = timeSlices as? [[String: Any]]
        let handler = recordSlicesHandler
        recordSlicesHandler = nil
        DispatchQueue.main.async { handler?(list, nil) }
    }

    // 静音状态
    func camera(_ camera: ThingSmartCameraType!, didReceiveMuteState isMute: Bool, playMode: ThingSmartCameraPlayMode) {
        isMuted = isMute
        DispatchQueue.main.async { self.forEachDelegate { $0.cameraMuteChanged?(self, muted: isMute) } }
    }

    // 错误
    func camera(_ camera: ThingSmartCameraType!, didOccurredErrorAtStep errStepCode: ThingCameraErrorCode, specificErrorCode errorCode: Int) {
        isConnected = false
        let err = NSError(domain: "ThingCamera", code: errorCode,
                          userInfo: [NSLocalizedDescriptionKey: "相机错误 step=\(errStepCode.rawValue) code=\(errorCode)"])
        DispatchQueue.main.async { self.forEachDelegate { $0.cameraDidError?(self, error: err) } }
    }

    func camera(_ camera: ThingSmartCameraType!, didOccurredErrorAtStep errStepCode: ThingCameraErrorCode, specificErrorCode errorCode: Int, extErrorCodeInfo: Any!) { }

    // 分辨率变化
    func camera(_ camera: ThingSmartCameraType!, resolutionDidChangeWidth width: Int, height: Int) { }
    func camera(_ camera: ThingSmartCameraType!, resolutionDidChangeWith videoExtInfo: Any!) { }

    // 原始帧数据（本 Demo 不处理）；逐帧视频回调已用于卡顿体检，实现见上方
    func camera(_ camera: ThingSmartCameraType!, thing_didReceiveFrameData frameData: UnsafePointer<CChar>!, dataSize: UInt32, frameInfo: ThingSmartVideoStreamInfo) { }
    func camera(_ camera: ThingSmartCameraType!, didReceiveLocalVideoSampleBuffer sampleBuffer: CMSampleBuffer!, localVideoInfo: Any!) { }
    func camera(_ camera: ThingSmartCameraType!, thing_didRecieveAudioRecordDataWithPCM pcm: UnsafePointer<UInt8>!, length: Int32, sampleRate: Int32) { }
    func camera(_ camera: ThingSmartCameraType!, thing_didSpeedPlayWith speed: ThingSmartCameraPlayBackSpeed) { }
    func camera(_ camera: (any ThingSmartCameraType)!, thing_didEventReceivedEventType event: Int, errorCode error: Int, intValue: Int64, strValue: String!) { }
}

// MARK: - 会话托管（本次「多次进出后卡」的核心修复）

/// 按 devId 复用同一条 P2P 会话，页面只负责 attach/detach，不再各自 new CameraController。
///
/// 解决的问题：
/// · `viewDidAppear` 每次重复 connect → 同一设备堆积多条会话，设备并发会话被自己占满
///   （表现为第 N 次「已连接但拿不到首帧」，服务端可见 close_reason=12 / -23 / -104）；
/// · 预览页 + 回放页各建一个 camera 对象 → 一次进出占用 2 条并发会话；
/// · 退出页面不释放渲染视图 → 多个 GL 上下文共存，越进越卡。
///
/// 规则：
/// · 引用计数归零后延迟 `idleRelease` 秒才真正 teardown，因此去「本地相册 / 消息中心」
///   这类与摄像无关的页面再返回时可原样复用，不重连、不闪黑屏；
/// · 明确退出预览/回放（`isMovingFromParent`）时由调用方传 `immediate: true` 立刻释放；
/// · 退到后台断通道、回前台自动重连（仅当仍有页面持有该会话）。
final class CameraSessionManager: NSObject {

    static let shared = CameraSessionManager()

    /// 无页面持有后，多久真正释放会话（秒）
    private let idleRelease: TimeInterval = 30

    private var sessions: [String: CameraController] = [:]
    private var refs: [String: Int] = [:]
    private var idleTasks: [String: DispatchWorkItem] = [:]

    private override init() {
        super.init()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(onEnterBackground),
                       name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(onEnterForeground),
                       name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    /// 页面进入时调用：拿到（并按需新建/复用）会话，内部已做幂等 connect
    @discardableResult
    func acquire(devId: String, delegate: CameraControllerDelegate?) -> CameraController {
        cancelIdleRelease(devId)

        let controller: CameraController
        if let existing = sessions[devId], !existing.isReleased {
            controller = existing
        } else {
            controller = CameraController(devId: devId)
            sessions[devId] = controller
        }
        if let delegate = delegate { controller.addHandler(delegate) }
        refs[devId, default: 0] += 1
        controller.connect()
        return controller
    }

    /// 页面离开时调用。immediate=true 表示真正退出（pop/dismiss），需要马上释放会话。
    func release(devId: String, delegate: CameraControllerDelegate?, immediate: Bool = false) {
        guard let controller = sessions[devId] else { return }
        if let delegate = delegate { controller.removeHandler(delegate) }
        let remaining = max(0, (refs[devId] ?? 0) - 1)
        refs[devId] = remaining
        guard remaining == 0 else { return }

        if immediate {
            forceRelease(devId)
            return
        }
        let task = DispatchWorkItem { [weak self, weak controller] in
            guard let self = self, self.refs[devId] == 0,
                  let controller = controller, !controller.isReleased else { return }
            controller.teardown()
            if self.sessions[devId] === controller { self.sessions[devId] = nil }
        }
        idleTasks[devId] = task
        DispatchQueue.main.asyncAfter(deadline: .now() + idleRelease, execute: task)
    }

    /// 页面 deinit 兜底：只摘回调，不动引用计数（计数由 acquire/release 成对负责）
    func detach(devId: String, delegate: CameraControllerDelegate?) {
        if let delegate = delegate { sessions[devId]?.removeHandler(delegate) }
    }

    func forceRelease(_ devId: String) {
        cancelIdleRelease(devId)
        sessions[devId]?.teardown()
        sessions[devId] = nil
        refs[devId] = 0
    }

    private func cancelIdleRelease(_ devId: String) {
        idleTasks[devId]?.cancel()
        idleTasks[devId] = nil
    }

    @objc private func onEnterBackground() {
        for (devId, controller) in sessions where (refs[devId] ?? 0) > 0 {
            controller.stopPreview()
            controller.disconnect()
        }
    }

    @objc private func onEnterForeground() {
        for (devId, controller) in sessions where (refs[devId] ?? 0) > 0 {
            controller.connect()
        }
    }
}
