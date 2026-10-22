import UIKit
import AVKit
import Photos

/// 本地相册（对应 Android CameraAlbumActivity）：浏览本 App 截图 / 录像落盘的文件。
///
/// 性能约定（本次优化）：
/// · 目录扫描与图片解码一律不放主线程，否则文件一多就会在进入页面时掉帧；
/// · 打开录像用 AVPlayerViewControllerDelegate 在停止播放时 pause，及时释放解码资源；
/// · 列表 cell 需要副标题，故自定义 cell —— UITableView(style: .plain) 的默认 cell
///   没有 detailTextLabel，原来的 "录像/截图" 标签其实一直没显示。
final class CameraAlbumViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, AVPlayerViewControllerDelegate {

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyLabel = UILabel()
    private var items: [URL] = []
    /// 强持有当前播放器，配合 delegate 在停止时 pause
    private var player: AVPlayer?
    /// 扫描任务令牌：页面快速进出时丢弃过期结果，避免旧列表覆盖新列表
    private var scanToken = 0
    private static let cellId = "albumCell"

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "本地相册"
        view.backgroundColor = .white
        setupUI()
        reload()
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "刷新", style: .plain, target: self, action: #selector(reload))
    }

    private func setupUI() {
        tableView.dataSource = self; tableView.delegate = self
        tableView.register(SubtitleCell.self, forCellReuseIdentifier: Self.cellId)
        tableView.rowHeight = 60
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        emptyLabel.text = "暂无本地媒体，请先截图或录像"; emptyLabel.textColor = .gray
        emptyLabel.textAlignment = .center; emptyLabel.isHidden = true
        view.addSubview(emptyLabel)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    /// 后台扫描沙盒目录，回主线程刷新，避免大量文件时的主线程 I/O 卡顿
    @objc private func reload() {
        scanToken += 1
        let token = scanToken
        emptyLabel.text = "扫描中…"
        emptyLabel.isHidden = false
        IpcLocalMediaHelper.ioQueue.async {
            let list = IpcLocalMediaHelper.listLocalMedia()
            DispatchQueue.main.async {
                guard token == self.scanToken else { return }   // 已被更新的扫描取代
                self.items = list
                self.tableView.reloadData()
                self.emptyLabel.isHidden = !list.isEmpty
                self.emptyLabel.text = "暂无本地媒体，请先截图或录像"
            }
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellId, for: indexPath) as! SubtitleCell
        let url = items[indexPath.row]
        let isVideo = url.pathExtension.lowercased() == "mp4"
        cell.configure(title: url.lastPathComponent, subtitle: isVideo ? "录像" : "截图")
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let url = items[indexPath.row]
        if url.pathExtension.lowercased() == "mp4" {
            let player = AVPlayer(url: url)
            let vc = AVPlayerViewController()
            vc.delegate = self
            vc.player = player
            self.player = player
            present(vc, animated: true) { player.play() }
        } else {
            showImage(from: url)
        }
    }

    /// 全尺寸 JPEG 解码放到后台队列，主线程只做赋值
    private func showImage(from url: URL) {
        let vc = UIViewController(); vc.view.backgroundColor = .black
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        iv.frame = vc.view.bounds
        vc.view.addSubview(iv)
        let nav = UINavigationController(rootViewController: vc)
        vc.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(closePreview))
        present(nav, animated: true)
        IpcLocalMediaHelper.ioQueue.async {
            let image = UIImage(contentsOfFile: url.path)
            DispatchQueue.main.async { iv.image = image }
        }
    }

    @objc private func closePreview() { dismiss(animated: true) }

    /// 关闭录像播放器时立即停止播放，释放解码与音频占用
    func playerViewControllerDidStop(_ playerViewController: AVPlayerViewController) {
        player?.pause()
        player = nil
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let url = items[indexPath.row]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let del = UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                IpcLocalMediaHelper.ioQueue.async {
                    try? FileManager.default.removeItem(at: url)
                    DispatchQueue.main.async { self.reload() }
                }
            }
            return UIMenu(title: "", children: [del])
        }
    }
}

/// 带副标题的简单 cell（iOS 13 也可用，不依赖 UIListContentConfiguration）
private final class SubtitleCell: UITableViewCell {

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        titleLabel.font = .systemFont(ofSize: 15)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabel
        accessoryType = .disclosureIndicator
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -40)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, subtitle: String) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
    }
}
