import UIKit
import AVFoundation
import ThingSmartCameraKit

// MARK: - 渐变蒙层（顶部状态条，提升可读性又不挡画面）
final class GradientView: UIView {
    private let grad = CAGradientLayer()
    init(top: UIColor, bottom: UIColor, vertical: Bool = true) {
        super.init(frame: .zero)
        grad.colors = [top.cgColor, bottom.cgColor]
        grad.locations = [0, 1]
        grad.startPoint = vertical ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
        grad.endPoint   = vertical ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
        layer.addSublayer(grad)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        grad.frame = bounds
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 底部控件按钮（圆形图标 + 下方小字，半透明描边）
final class ControlButton: UIButton {
    private let iconCircle = UIView()
    private let iconView = UIImageView()
    private let titleView = UILabel()
    private let inner = UIStackView()

    var iconName: String = "" {
        didSet { iconView.image = UIImage(systemName: iconName)?.withRenderingMode(.alwaysTemplate) }
    }

    init(icon: String, title: String) {
        super.init(frame: .zero)
        iconCircle.backgroundColor = UIColor(white: 0, alpha: 0.42)
        iconCircle.layer.cornerRadius = 26
        iconCircle.layer.borderWidth = 1
        iconCircle.layer.borderColor = UIColor(white: 1, alpha: 0.18).cgColor
        iconCircle.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconCircle.addSubview(iconView)

        titleView.text = title
        titleView.textColor = .white
        titleView.font = .systemFont(ofSize: 10, weight: .medium)
        titleView.textAlignment = .center
        titleView.lineBreakMode = .byTruncatingTail
        titleView.translatesAutoresizingMaskIntoConstraints = false

        inner.axis = .vertical
        inner.alignment = .center
        inner.spacing = 5
        inner.addArrangedSubview(iconCircle)
        inner.addArrangedSubview(titleView)
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.isUserInteractionEnabled = false
        addSubview(inner)

        NSLayoutConstraint.activate([
            inner.centerXAnchor.constraint(equalTo: centerXAnchor),
            inner.centerYAnchor.constraint(equalTo: centerYAnchor),
            inner.topAnchor.constraint(equalTo: topAnchor),
            inner.bottomAnchor.constraint(equalTo: bottomAnchor),
            iconCircle.widthAnchor.constraint(equalToConstant: 52),
            iconCircle.heightAnchor.constraint(equalToConstant: 52),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),
            iconView.centerXAnchor.constraint(equalTo: iconCircle.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconCircle.centerYAnchor)
        ])
        iconName = icon
    }

    func set(icon: String, title: String) {
        iconName = icon
        titleView.text = title
    }

    /// 激活态高亮（对讲中/录制中）
    func setActive(_ active: Bool, highlight: UIColor? = nil) {
        iconCircle.backgroundColor = active ? (highlight ?? .systemOrange) : UIColor(white: 0, alpha: 0.42)
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// 实时预览面板（对应 Android CameraPanelActivity）：
/// 预览固定在屏幕上半部分，控制区（云台方向键 + 功能按钮）固定在屏幕下方，
/// 云台不再浮在画面中央。全屏时预览铺满并旋转为横屏观感。
final class CameraPanelViewController: UIViewController, CameraControllerDelegate, UIGestureRecognizerDelegate {

    private let devId: String
    /// 会话由 CameraSessionManager 按 devId 托管，本页面只是持有者之一
    private var controller: CameraController?
    private let isDoorbell: Bool
    private var isFullscreen = false
    private var zoomScale: CGFloat = 1.0
    /// 主动离开页面（stopPreview）时置位，避免误把"已停止预览"闪出来
    private var intentionallyStopping = false
    /// 自适应重起播过程中，同样不该提示"已停止预览"
    private var autoAdjusting = false

    // MARK: UI
    /// 内容容器：始终铺满整屏；全屏时整体旋转 90° 形成横屏观感。预览/控制均为其子视图。
    private let containerView = UIView()
    /// 预览层（GL 渲染视图挂在它里面），占据屏幕上半部分
    private let previewContainer = UIView()
    /// 预览底部约束：竖屏时贴住底部控制区顶；全屏时改贴容器底（铺满）
    private var previewBottomToPanel: NSLayoutConstraint!
    private var previewBottomToContainer: NSLayoutConstraint!

    /// 顶部渐变条（返回 + 状态），浮在预览上方
    private let topBar = GradientView(top: UIColor(white: 0, alpha: 0.55), bottom: .clear)
    private let backBtn = UIButton(type: .system)
    private let statusLabel = UILabel()

    /// 底部控制区：云台方向键 + 功能按钮，固定在屏幕下方
    private let bottomPanel = UIView()
    private let ptzCluster = UIView()
    private let ptzUp = UIButton(type: .system)
    private let ptzDown = UIButton(type: .system)
    private let ptzLeft = UIButton(type: .system)
    private let ptzRight = UIButton(type: .system)

    private let fullscreenBtn = ControlButton(icon: "arrow.up.left.and.arrow.down.right", title: "全屏")
    private let modeBtn = ControlButton(icon: "ellipsis", title: "更多")
    private let muteBtn = ControlButton(icon: "speaker.slash.fill", title: "静音")
    private let talkBtn = ControlButton(icon: "mic.fill", title: "对讲")
    private let snapBtn = ControlButton(icon: "camera.fill", title: "截图")
    private let recBtn = ControlButton(icon: "record.circle", title: "录像")
    private let defBtn = ControlButton(icon: "hd", title: "高清")
    private let bottomStack = UIStackView()

    /// 全屏时的浮层控制条：把竖屏那一排功能按钮搬进来（对讲/静音/截图/录像/清晰度仍然可用）。
    /// 复用同一批按钮实例，状态回调里对 muteBtn/talkBtn 的更新就不需要同步两份。
    private let fsControlBar = UIView()
    /// 当前生效的功能行约束。换父视图前必须先 deactivate，否则会留下跨层级的失效约束。
    private var functionRowConstraints: [NSLayoutConstraint] = []
    /// 顶部条在竖屏/全屏下的几何差异（全屏是旋转后的本地坐标，需换一组内缩）
    private var topBarHeight: NSLayoutConstraint!
    private var backBtnTop: NSLayoutConstraint!
    private var backBtnLeading: NSLayoutConstraint!
    private var backBtnWidth: NSLayoutConstraint!

    init(devId: String) {
        self.devId = devId
        self.isDoorbell = DeviceCapability.resolveDeviceType(devId) == 2
        super.init(nibName: nil, bundle: nil)
        // ⚠️ 不在这里创建会话：历史上「init 里 new CameraController + viewDidAppear 里 connect」
        // 会让每次从相册/回放返回都重新建一条 P2P 通道，会话堆积是页面变卡的主因。
        // 现在统一在 viewDidAppear 向 CameraSessionManager 申请（内部幂等）。
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // ★ 音频会话预配置：必须在进页面、启动预览/对讲之前就把 AVAudioSession
        // 设为 playAndRecord + defaultToSpeaker（涂鸦官方 IPC Demo 标准做法）。
        // 否则 SDK 在连接后自动配置音频会报 -50 / defaultToSpeaker 类别错误，
        // 进而拖垮整条 P2P 连接导致反复重连、间歇"已停止预览"。
        // 注意：这里只设类别、不 setActive，避免与相册里的 AVPlayer 抢音频会话。
        configureAudioSessionCategory()
        setupUI()
        setupGestures()
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !isFullscreen && containerView.transform == .identity {
            containerView.frame = view.bounds
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        navigationController?.interactivePopGestureRecognizer?.delegate = self
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 转场动画结束后再建会话：既不拖慢 push 动画，也保证同一 devId 只有一条通道
        controller = CameraSessionManager.shared.acquire(devId: devId, delegate: self)
        ensurePreviewViewAdded()
        if controller?.isConnected == true {
            // 复用已有通道（例如刚从本地相册返回）：不会再触发 cameraDidConnected，需手动起预览
            intentionallyStopping = false
            controller?.startPreview()
            statusLabel.text = "已连接，启动预览…"
        } else {
            statusLabel.text = "连接中…"
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        intentionallyStopping = true
        // 离开本页时收回全屏，返回时是正常竖屏预览（页面还在栈里，不会丢会话）
        if isFullscreen { exitFullscreen() }
        controller?.stopPreview()
        controller?.stopTalk()
        if controller?.isRecording == true { controller?.stopRecord() }
        navigationController?.setNavigationBarHidden(false, animated: animated)
        if navigationController?.interactivePopGestureRecognizer?.delegate === self {
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
        // ★ 关键：区分「只是 push 到子页面」和「真正退出」。
        // 去相册/消息等页面 → 保留会话（30 秒空闲后自动释放），返回时原样复用不再重连；
        // 真正 pop/dismiss → 立即断连并摘掉渲染视图，释放解码器与 GL 上下文。
        let leavingForever = isMovingFromParent || isBeingDismissed
        CameraSessionManager.shared.release(devId: devId, delegate: self, immediate: leavingForever)
        if leavingForever { deactivateAudioSession() }
    }

    deinit {
        // 只反注册回调；会话释放已由 viewWillDisappear 的 release(immediate:) 完成，
        // 这里再兜一次，防止手势返回等特殊路径漏放。
        CameraSessionManager.shared.detach(devId: devId, delegate: self)
    }

    // MARK: - AVAudioSession（关键：保证声音/对讲可用且连接稳定）
    /// 只设类别，不激活：避免每次进页面都 setActive(true) 与相册 AVPlayer 抢占音频会话
    private func configureAudioSessionCategory() {
        do {
            try AVAudioSession.sharedInstance()
                .setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers])
        } catch {
            #if DEBUG
            print("[Panel] AVAudioSession 类别设置失败：\(error.localizedDescription)")
            #endif
        }
    }

    /// 真正需要出声/对讲时才激活
    private func activateAudioSession() {
        configureAudioSessionCategory()
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            #if DEBUG
            print("[Panel] AVAudioSession 激活失败：\(error.localizedDescription)")
            #endif
        }
    }

    /// 彻底离开预览页时释放，把音频设备还给系统/其它播放器
    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            #if DEBUG
            print("[Panel] AVAudioSession 释放失败（可忽略）：\(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - 返回键：先回预览，再回列表
    @objc private func onBack() {
        if isFullscreen {
            exitFullscreen()
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === navigationController?.interactivePopGestureRecognizer {
            if isFullscreen {
                exitFullscreen()
                return false
            }
        }
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    // MARK: - UI 搭建
    private func setupUI() {
        containerView.backgroundColor = .black
        containerView.autoresizingMask = []
        view.addSubview(containerView)
        containerView.frame = view.bounds

        previewContainer.backgroundColor = .black
        previewContainer.isUserInteractionEnabled = true
        containerView.addSubview(previewContainer)
        previewContainer.translatesAutoresizingMaskIntoConstraints = false

        setupTopBar()
        setupBottomPanel()
        setupPtz()
        setupFullscreenControlBar()

        let g = containerView.safeAreaLayoutGuide
        // 预览：顶到容器顶，底部默认贴住底部控制区；全屏时切到贴容器底铺满。
        previewBottomToPanel = previewContainer.bottomAnchor.constraint(equalTo: bottomPanel.topAnchor)
        previewBottomToContainer = previewContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        previewBottomToContainer.isActive = false
        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: containerView.topAnchor),
            previewContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            previewContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            previewBottomToPanel,

            topBar.topAnchor.constraint(equalTo: containerView.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),

            bottomPanel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            bottomPanel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            bottomPanel.bottomAnchor.constraint(equalTo: g.bottomAnchor),
            bottomPanel.heightAnchor.constraint(equalTo: containerView.heightAnchor, multiplier: 0.42)
        ])
        // 渲染视图改由 viewDidAppear 拿到托管会话后挂载（此处 controller 尚未创建）
    }

    private func setupTopBar() {
        containerView.addSubview(topBar)
        topBar.translatesAutoresizingMaskIntoConstraints = false

        backBtn.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backBtn.tintColor = .white
        backBtn.titleLabel?.font = .systemFont(ofSize: 24, weight: .semibold)
        backBtn.backgroundColor = UIColor(white: 0, alpha: 0.38)
        backBtn.layer.cornerRadius = 19
        backBtn.clipsToBounds = true
        backBtn.addTarget(self, action: #selector(onBack), for: .touchUpInside)
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(backBtn)

        statusLabel.text = "连接中…"
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(statusLabel)

        topBarHeight = topBar.heightAnchor.constraint(equalToConstant: 88)
        backBtnLeading = backBtn.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 14)
        backBtnTop = backBtn.topAnchor.constraint(equalTo: topBar.topAnchor, constant: 44)
        backBtnWidth = backBtn.widthAnchor.constraint(equalToConstant: 38)
        NSLayoutConstraint.activate([
            topBarHeight,
            backBtnLeading,
            backBtnTop,
            backBtnWidth,
            backBtn.heightAnchor.constraint(equalToConstant: 38),

            statusLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: backBtn.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: backBtn.trailingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: topBar.trailingAnchor, constant: -14)
        ])
    }

    // MARK: - 全屏浮层控制条
    /// 只在横屏铺满时出现：贴在旋转后画面的下沿，承载同一排功能按钮
    private func setupFullscreenControlBar() {
        fsControlBar.isHidden = true
        fsControlBar.backgroundColor = UIColor(white: 0, alpha: 0.38)
        fsControlBar.layer.cornerRadius = 20
        fsControlBar.layer.borderWidth = 1
        fsControlBar.layer.borderColor = UIColor(white: 1, alpha: 0.14).cgColor
        fsControlBar.clipsToBounds = true
        fsControlBar.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(fsControlBar)

        NSLayoutConstraint.activate([
            // 旋转后刘海压在本地左沿，浮层整体让开 44
            fsControlBar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 44),
            fsControlBar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -32),
            fsControlBar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
            fsControlBar.heightAnchor.constraint(equalToConstant: 92)
        ])
    }

    /// 把功能按钮行在「竖屏底部面板」与「全屏浮层条」之间搬动
    private func relocateFunctionRow(to host: UIView, leading: CGFloat, trailing: CGFloat, bottom: CGFloat, height: CGFloat) {
        functionRowConstraints.forEach { $0.isActive = false }
        functionRowConstraints = []
        bottomStack.removeFromSuperview()
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(bottomStack)
        functionRowConstraints = [
            bottomStack.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: leading),
            bottomStack.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: trailing),
            bottomStack.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: bottom),
            bottomStack.heightAnchor.constraint(equalToConstant: height)
        ]
        NSLayoutConstraint.activate(functionRowConstraints)
    }

    private func setupBottomPanel() {
        containerView.addSubview(bottomPanel)
        bottomPanel.translatesAutoresizingMaskIntoConstraints = false
        bottomPanel.backgroundColor = UIColor(white: 0.07, alpha: 1)
        // 顶部一条细分割线，和预览区视觉区隔
        let hair = UIView()
        hair.backgroundColor = UIColor(white: 1, alpha: 0.08)
        hair.translatesAutoresizingMaskIntoConstraints = false
        bottomPanel.addSubview(hair)
        NSLayoutConstraint.activate([
            hair.topAnchor.constraint(equalTo: bottomPanel.topAnchor),
            hair.leadingAnchor.constraint(equalTo: bottomPanel.leadingAnchor),
            hair.trailingAnchor.constraint(equalTo: bottomPanel.trailingAnchor),
            hair.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ])

        // 功能按钮行
        fullscreenBtn.addTarget(self, action: #selector(onFullscreen), for: .touchUpInside)
        modeBtn.addTarget(self, action: #selector(onMode), for: .touchUpInside)
        muteBtn.addTarget(self, action: #selector(onMute), for: .touchUpInside)
        talkBtn.addTarget(self, action: #selector(onTalk), for: .touchUpInside)
        snapBtn.addTarget(self, action: #selector(onSnapshot), for: .touchUpInside)
        recBtn.addTarget(self, action: #selector(onRecord), for: .touchUpInside)
        defBtn.addTarget(self, action: #selector(onDefinition), for: .touchUpInside)
        modeBtn.set(icon: "ellipsis", title: isDoorbell ? "视频通话" : "更多")

        let btns = [fullscreenBtn, modeBtn, muteBtn, talkBtn, snapBtn, recBtn, defBtn]
        btns.forEach { bottomStack.addArrangedSubview($0) }
        bottomStack.axis = .horizontal
        bottomStack.distribution = .fillEqually
        bottomStack.alignment = .center
        bottomStack.spacing = 4
        // 约束统一交给 relocateFunctionRow 管理：竖屏挂底部面板，全屏时整排搬到浮层条上
        relocateFunctionRow(to: bottomPanel, leading: 8, trailing: -8, bottom: -14, height: 76)
    }

    @objc private func onMode() {
        if isDoorbell { onVideoCall() } else { onMore() }
    }

    private func setupPtz() {
        bottomPanel.addSubview(ptzCluster)
        ptzCluster.translatesAutoresizingMaskIntoConstraints = false
        ptzCluster.backgroundColor = .clear

        for (btn, glyph) in [(ptzUp, "arrow.up"), (ptzDown, "arrow.down"),
                             (ptzLeft, "arrow.left"), (ptzRight, "arrow.right")] {
            btn.setImage(UIImage(systemName: glyph), for: .normal)
            btn.tintColor = .white
            btn.backgroundColor = UIColor(white: 0, alpha: 0.34)
            btn.layer.cornerRadius = 26
            btn.layer.borderWidth = 1
            btn.layer.borderColor = UIColor(white: 1, alpha: 0.16).cgColor
            btn.clipsToBounds = true
            btn.translatesAutoresizingMaskIntoConstraints = false
            ptzCluster.addSubview(btn)
        }
        bindPtz(ptzUp, .up); bindPtz(ptzDown, .down); bindPtz(ptzLeft, .left); bindPtz(ptzRight, .right)

        let s: CGFloat = 52
        let clusterSize: CGFloat = 150
        NSLayoutConstraint.activate([
            ptzCluster.centerXAnchor.constraint(equalTo: bottomPanel.centerXAnchor),
            ptzCluster.topAnchor.constraint(equalTo: bottomPanel.topAnchor, constant: 18),
            ptzCluster.widthAnchor.constraint(equalToConstant: clusterSize),
            ptzCluster.heightAnchor.constraint(equalToConstant: clusterSize),

            ptzUp.widthAnchor.constraint(equalToConstant: s), ptzUp.heightAnchor.constraint(equalToConstant: s),
            ptzUp.centerXAnchor.constraint(equalTo: ptzCluster.centerXAnchor),
            ptzUp.topAnchor.constraint(equalTo: ptzCluster.topAnchor),

            ptzDown.widthAnchor.constraint(equalToConstant: s), ptzDown.heightAnchor.constraint(equalToConstant: s),
            ptzDown.centerXAnchor.constraint(equalTo: ptzCluster.centerXAnchor),
            ptzDown.bottomAnchor.constraint(equalTo: ptzCluster.bottomAnchor),

            ptzLeft.widthAnchor.constraint(equalToConstant: s), ptzLeft.heightAnchor.constraint(equalToConstant: s),
            ptzLeft.centerYAnchor.constraint(equalTo: ptzCluster.centerYAnchor),
            ptzLeft.leadingAnchor.constraint(equalTo: ptzCluster.leadingAnchor),

            ptzRight.widthAnchor.constraint(equalToConstant: s), ptzRight.heightAnchor.constraint(equalToConstant: s),
            ptzRight.centerYAnchor.constraint(equalTo: ptzCluster.centerYAnchor),
            ptzRight.trailingAnchor.constraint(equalTo: ptzCluster.trailingAnchor)
        ])
    }

    private func setupGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        previewContainer.addGestureRecognizer(pinch)
        let dbl = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap))
        dbl.numberOfTapsRequired = 2
        previewContainer.addGestureRecognizer(dbl)
    }

    // MARK: - 手势
    @objc private func onPinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .changed {
            zoomScale = min(max(zoomScale * g.scale, 1.0), 4.0)
            controller?.zoom(zoomScale)
            g.scale = 1.0
        }
    }
    @objc private func onDoubleTap() {
        zoomScale = (zoomScale > 1.0) ? 1.0 : 2.0
        controller?.zoom(zoomScale)
    }

    // MARK: - 全屏横屏（预览铺满 + 内容视图 transform 旋转，不触碰设备方向）
    @objc private func onFullscreen() {
        isFullscreen ? exitFullscreen() : enterFullscreen()
    }

    private func enterFullscreen() {
        guard !isFullscreen else { return }
        isFullscreen = true
        fullscreenBtn.set(icon: "arrow.down.right.and.arrow.up.left", title: "退出")

        // 隐藏底部控制区，预览改贴容器底铺满
        bottomPanel.isHidden = true
        previewBottomToPanel.isActive = false
        previewBottomToContainer.isActive = true

        // 功能按钮搬到画面下沿的浮层：全屏时同样能对讲 / 静音 / 截图 / 录像 / 切清晰度
        relocateFunctionRow(to: fsControlBar, leading: 12, trailing: -12, bottom: -8, height: 76)
        fsControlBar.isHidden = false
        applyTopBarLayout(fullscreen: true)

        let screen = UIScreen.main.bounds
        containerView.transform = CGAffineTransform(rotationAngle: .pi / 2)
        containerView.bounds = CGRect(x: 0, y: 0, width: screen.size.height, height: screen.size.width)
        containerView.center = CGPoint(x: screen.size.width / 2, y: screen.size.height / 2)

        ensurePreviewViewAdded()
        view.setNeedsLayout()
        UIView.animate(withDuration: 0.28) { self.view.layoutIfNeeded() }
    }

    private func exitFullscreen() {
        guard isFullscreen else { return }
        isFullscreen = false
        fullscreenBtn.set(icon: "arrow.up.left.and.arrow.down.right", title: "全屏")

        previewBottomToContainer.isActive = false
        previewBottomToPanel.isActive = true
        bottomPanel.isHidden = false

        // 按钮行搬回竖屏底部面板，浮层收起
        relocateFunctionRow(to: bottomPanel, leading: 8, trailing: -8, bottom: -14, height: 76)
        fsControlBar.isHidden = true
        applyTopBarLayout(fullscreen: false)

        containerView.transform = .identity
        containerView.bounds = view.bounds
        containerView.center = CGPoint(x: view.bounds.width / 2, y: view.bounds.height / 2)

        ensurePreviewViewAdded()
        view.setNeedsLayout()
        UIView.animate(withDuration: 0.28) { self.view.layoutIfNeeded() }
    }

    /// 顶部条在竖屏/全屏下的差异：全屏是旋转后的本地坐标，刘海压在本地左沿，返回键要让开并留出文字位
    private func applyTopBarLayout(fullscreen: Bool) {
        topBarHeight.constant = fullscreen ? 60 : 88
        backBtnTop.constant = fullscreen ? 11 : 44
        backBtnLeading.constant = fullscreen ? 44 : 14
        backBtnWidth.constant = fullscreen ? 104 : 38
        // 带一个前导空格充当图标与文字之间的间距，避免用 iOS15 起废弃的 contentEdgeInsets
        backBtn.setTitle(fullscreen ? " 返回" : "", for: .normal)
        backBtn.titleLabel?.font = .systemFont(ofSize: fullscreen ? 15 : 24, weight: .semibold)
        // 全屏时左上角「返回」已承担退出，行内再放一个「退出」是重复入口
        fullscreenBtn.isHidden = fullscreen
    }

    // MARK: - 控制按钮
    @objc private func onMute() {
        guard let c = controller else { return }
        // 切声音/静音前确保音频会话已就位，避免 SDK 内部音频初始化再次报错
        activateAudioSession()
        c.setMuted(!c.isMuted)
    }
    @objc private func onTalk() {
        guard let c = controller else { return }
        activateAudioSession()
        if c.isTalking { c.stopTalk() } else { c.startTalk() }
    }
    @objc private func onSnapshot() { controller?.snapshot() }
    @objc private func onRecord() {
        guard let c = controller else { return }
        if c.isRecording {
            c.stopRecord()
        } else {
            let url = IpcLocalMediaHelper.localMediaDir
                .appendingPathComponent("\(devId)_\(Date().timeIntervalSince1970).mp4")
            c.startRecord(to: url.path)
        }
    }
    @objc private func onDefinition() {
        guard let c = controller else { return }
        c.setHD(!c.isHD)
        updateBottomTitles()
    }
    @objc private func onVideoCall() {
        guard let c = controller else { return }
        activateAudioSession()
        if c.isTalking { c.stopTalk() } else { c.startTalk() }
        showToast("门铃视频通话：已通过对讲通道建立")
    }
    /// 云台按钮：按住转动，松开停止
    private func bindPtz(_ button: UIButton, _ direction: ThingSmartPTZControlDirection) {
        button.addTarget(self, action: #selector(ptzTouchDown(_:)), for: .touchDown)
        button.addTarget(self, action: #selector(ptzTouchUp(_:)), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        button.accessibilityIdentifier = "\(direction.rawValue)"
    }

    @objc private func ptzTouchDown(_ sender: UIButton) {
        guard let raw = sender.accessibilityIdentifier, let dir = UInt(raw), let d = ThingSmartPTZControlDirection(rawValue: dir) else { return }
        controller?.startPTZ(d)
    }

    @objc private func ptzTouchUp(_ sender: UIButton) {
        controller?.stopPTZ()
    }

    @objc private func onMore() {
        let sheet = UIAlertController(title: "更多功能", message: nil, preferredStyle: .actionSheet)
        let actions: [(String, Selector)] = [
            ("卡录像回放", #selector(goPlayback)),
            ("云存储", #selector(goCloud)),
            ("SD 卡管理", #selector(goSd)),
            ("消息中心", #selector(goMessage)),
            ("视频消息", #selector(goVideoMessage)),
            ("本地相册", #selector(goAlbum))
        ]
        actions.forEach { title, sel in
            sheet.addAction(UIAlertAction(title: title, style: .default, handler: { [weak self] _ in self?.perform(sel) }))
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }
    @objc private func goPlayback() { push(CameraPlaybackViewController(devId: devId)) }
    @objc private func goCloud() { push(CameraCloudStorageViewController(devId: devId)) }
    @objc private func goSd() { push(CameraSdManageViewController(devId: devId)) }
    @objc private func goMessage() { push(CameraMessageViewController(devId: devId)) }
    @objc private func goVideoMessage() { push(CameraVideoMessageViewController(devId: devId)) }
    @objc private func goAlbum() { push(CameraAlbumViewController()) }
    private func push(_ vc: UIViewController) { navigationController?.pushViewController(vc, animated: true) }

    private func updateBottomTitles() {
        defBtn.set(icon: controller?.isHD == true ? "hd" : "h.circle",
                   title: controller?.isHD == true ? "高清" : "标清")
    }

    // MARK: - CameraControllerDelegate
    func cameraDidConnect(_ c: CameraController) {
        intentionallyStopping = false
        DispatchQueue.main.async {
            self.statusLabel.text = "已连接，启动预览…"
            self.controller?.startPreview()
        }
    }
    func cameraDidFailConnect(_ c: CameraController, error: Error?) {
        intentionallyStopping = false
        DispatchQueue.main.async { self.statusLabel.text = "连接失败"; self.showError(code: nil, message: error?.localizedDescription) }
    }
    func cameraDidStartPreview(_ c: CameraController) {
        intentionallyStopping = false
        autoAdjusting = false
        DispatchQueue.main.async {
            self.ensurePreviewViewAdded()
            self.statusLabel.text = "预览中"
        }
    }

    /// 体检自适应（自动降清晰度 / 重新起播）：给用户一句人话，别只是画面突然抖一下
    func cameraQualityAdjusted(_ c: CameraController, message: String) {
        autoAdjusting = true
        DispatchQueue.main.async {
            self.showToast(message)
            self.statusLabel.text = message
            self.updateBottomTitles()
        }
    }

    private func ensurePreviewViewAdded() {
        guard let pv = controller?.cameraVideoView() else {
            #if DEBUG
            print("[Panel] ⚠️ cameraVideoView 返回 nil（camera 尚未创建或 videoView 暂不可用）")
            #endif
            return
        }
        pv.translatesAutoresizingMaskIntoConstraints = false
        pv.backgroundColor = .black
        pv.isHidden = false
        // 会话可能被多个页面复用：只要当前父视图不是本容器的 previewContainer，就重新挂载，
        // 避免旧渲染图层滞留在已离屏的视图树上仍占 GPU（这是"进出几次后越来越卡"的一环）。
        if pv.superview !== previewContainer {
            pv.removeFromSuperview()
            previewContainer.addSubview(pv)
            NSLayoutConstraint.activate([
                pv.topAnchor.constraint(equalTo: previewContainer.topAnchor),
                pv.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
                pv.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
                pv.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor)
            ])
            #if DEBUG
            print("[Panel] 渲染视图已 add 到 previewContainer")
            #endif
        }
        if Thread.isMainThread {
            previewContainer.layoutIfNeeded()
        }
    }

    /// 仅在「非正常停止」时提示，避免离开页面时闪一下"已停止预览"
    func cameraDidStopPreview(_ c: CameraController) {
        guard !intentionallyStopping, !autoAdjusting else { return }
        DispatchQueue.main.async { self.statusLabel.text = "已停止预览" }
    }
    func cameraSnapshotSaved(_ c: CameraController, success: Bool) {
        DispatchQueue.main.async { self.showToast(success ? "截图已保存" : "截图失败") }
    }
    func cameraRecordingChanged(_ c: CameraController, recording: Bool) {
        DispatchQueue.main.async {
            self.statusLabel.text = recording ? "录制中…" : "预览中"
            self.recBtn.set(icon: recording ? "stop.circle" : "record.circle",
                            title: recording ? "录制中" : "录像")
            self.recBtn.setActive(recording, highlight: .systemRed)
            self.updateBottomTitles()
        }
    }
    func cameraMuteChanged(_ c: CameraController, muted: Bool) {
        DispatchQueue.main.async {
            self.muteBtn.set(icon: muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                             title: muted ? "静音" : "声音")
        }
    }
    func cameraTalkChanged(_ c: CameraController, talking: Bool) {
        DispatchQueue.main.async {
            self.talkBtn.set(icon: "mic.fill", title: talking ? "对讲中" : "对讲")
            self.talkBtn.setActive(talking, highlight: .systemOrange)
        }
    }
    func cameraDidError(_ c: CameraController, error: Error?) {
        DispatchQueue.main.async { self.showError(code: nil, message: error?.localizedDescription) }
    }
}
