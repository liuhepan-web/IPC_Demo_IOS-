import UIKit
import ThingSmartCameraKit

/// 卡录像回放（对应 Android CameraPlaybackActivity）：按天查询有录像的日期 → 拉取当天时间片段 → 时间轴拖拽播放。
final class CameraPlaybackViewController: UIViewController, CameraControllerDelegate {

    private let devId: String
    /// 与预览页共用 CameraSessionManager 托管的同一条会话（同一 devId 不再各开一条 P2P 通道）
    private var controller: CameraController?

    private let dateLabel = UILabel()
    private let prevDay = UIButton(type: .system)
    private let nextDay = UIButton(type: .system)
    private let playBtn = UIButton(type: .system)
    private let slider = UISlider()
    private let timeLabel = UILabel()
    private let statusLabel = UILabel()

    /// 当前回放日期（默认今天）
    private var currentDate = Date()
    /// 当天可播放时间片段（start/end 为当天秒偏移 0..86400）
    private var slices: [[String: Any]] = []
    private var playing = false

    init(devId: String) {
        self.devId = devId
        super.init(nibName: nil, bundle: nil)
        // ⚠️ 不在 init 里 new CameraController：否则与预览页各占一条设备并发会话，
        // 进出几次后设备侧会话被自己占满，表现为"已连接但拿不到首帧"。
        // 会话统一由 CameraSessionManager 按 devId 托管，见 viewDidLoad。
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "卡录像回放"
        view.backgroundColor = .white
        buildUI()
        controller = CameraSessionManager.shared.acquire(devId: devId, delegate: self)
        queryDay(Date())
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        controller?.stopPlayback()
        // 回放走独立通道，离开时立即整体释放会话，预览页返回时再按预览模式重建
        CameraSessionManager.shared.release(devId: devId, delegate: self, immediate: true)
    }
    deinit { CameraSessionManager.shared.detach(devId: devId, delegate: self) }

    private func buildUI() {
        dateLabel.textAlignment = .center; dateLabel.font = .systemFont(ofSize: 15, weight: .medium)
        [prevDay, nextDay, playBtn].forEach {
            $0.setTitleColor(.white, for: .normal)
            $0.backgroundColor = UIColor(hex: TuyaConfig.brandMain)
            $0.layer.cornerRadius = 8
        }
        prevDay.setTitle("‹ 前一天", for: .normal)
        nextDay.setTitle("后一天 ›", for: .normal)
        playBtn.setTitle("播放", for: .normal)
        prevDay.addTarget(self, action: #selector(onPrev), for: .touchUpInside)
        nextDay.addTarget(self, action: #selector(onNext), for: .touchUpInside)
        playBtn.addTarget(self, action: #selector(onPlay), for: .touchUpInside)

        slider.minimumValue = 0; slider.maximumValue = 86400
        slider.addTarget(self, action: #selector(onSeek), for: .valueChanged)

        timeLabel.text = "00:00:00"; timeLabel.textAlignment = .center
        statusLabel.text = "连接中…"; statusLabel.textColor = .gray; statusLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [dateLabel,
                                                   hStack([prevDay, nextDay]),
                                                   slider, timeLabel,
                                                   playBtn, statusLabel])
        stack.axis = .vertical; stack.spacing = 16
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func hStack(_ views: [UIView]) -> UIStackView {
        let s = UIStackView(arrangedSubviews: views)
        s.axis = .horizontal; s.spacing = 16; s.distribution = .fillEqually
        return s
    }

    // MARK: - 日期导航
    @objc private func onPrev() {
        currentDate = Calendar.current.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
        queryDay(currentDate)
    }
    @objc private func onNext() {
        currentDate = Calendar.current.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        queryDay(currentDate)
    }

    private func queryDay(_ date: Date) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        dateLabel.text = f.string(from: date)
        statusLabel.text = "查询录像片段…"
        playing = false; playBtn.setTitle("播放", for: .normal)
        controller?.queryRecordTimeSlices(date: date, completion: { [weak self] slices, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let slices = slices {
                    self.slices = slices
                    self.statusLabel.text = slices.isEmpty ? "当天无录像" : "共 \(slices.count) 段录像，点击播放"
                } else {
                    self.statusLabel.text = "查询失败"
                    self.showError(code: nil, message: error?.localizedDescription)
                }
            }
        })
    }

    // MARK: - 播放控制
    @objc private func onPlay() {
        if playing {
            controller?.pausePlayback(); playing = false; playBtn.setTitle("继续", for: .normal)
        } else {
            controller?.startPlayback(date: currentDate); playing = true; playBtn.setTitle("暂停", for: .normal)
        }
    }

    @objc private func onSeek() {
        controller?.seekPlayback(time: TimeInterval(slider.value))
    }

    private func fmt(_ sec: TimeInterval) -> String {
        let h = Int(sec) / 3600, m = (Int(sec) % 3600) / 60, s = Int(sec) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    // MARK: - CameraControllerDelegate
    func cameraDidConnect(_ c: CameraController) { DispatchQueue.main.async { self.statusLabel.text = "已连接" } }
    func cameraDidFailConnect(_ c: CameraController, error: Error?) {
        DispatchQueue.main.async { self.statusLabel.text = "连接失败"; self.showError(code: nil, message: error?.localizedDescription) }
    }
    func cameraDidStartPlayback(_ c: CameraController) {
        DispatchQueue.main.async { self.statusLabel.text = "回放中"; self.playing = true; self.playBtn.setTitle("暂停", for: .normal) }
    }
    func cameraDidStopPlayback(_ c: CameraController) {
        DispatchQueue.main.async { self.statusLabel.text = "回放结束"; self.playing = false; self.playBtn.setTitle("播放", for: .normal) }
    }
    func cameraPlaybackProgress(_ c: CameraController, playTime: TimeInterval, fileStart: TimeInterval, fileEnd: TimeInterval, status: Int) {
        DispatchQueue.main.async {
            self.slider.value = Float(playTime)
            self.timeLabel.text = self.fmt(playTime)
        }
    }
    func cameraDidError(_ c: CameraController, error: Error?) {
        DispatchQueue.main.async { self.showError(code: nil, message: error?.localizedDescription) }
    }
}
