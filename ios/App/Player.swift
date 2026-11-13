import AVFoundation
import MobileVLCKit
import UIKit

enum PlayerState: String { case connecting, playing, failed }

/// The player: the channel full screen on VLC's engine (MobileVLCKit), which plays what IPTV playlists hold: HLS,
/// MPEG-TS over HTTP, RTMP, RTSP, UDP. Always dark, every orientation. A bar with Back and the channel's name sits
/// at the top; while the channel plays it hides after 3 seconds and a tap shows or hides it. A channel that does
/// not start within 20 seconds, errors or ends shows "This channel did not play" with Try again.
final class PlayerScreen: UIViewController, VLCMediaPlayerDelegate {
    private let channel: Channel
    private let frozen: PlayerState?   // the replica's held state: nothing is played
    private let video = UIView()
    private let bar = UIView()
    private let back = UIControl()
    private let backIcon = IconView(Icon.back, size: 24, tint: .white)
    private let name: Label
    private let connecting = Label(Words.connecting, size: 15, color: .playerMuted, lineHeight: 24)
    private let cross = IconView(Icon.cross, size: 20, tint: .white)
    private let failed = Label(Words.didNotPlay, size: 15, color: .white, lineHeight: 24)
    private let again = Block(Words.again, fill: .white, textColor: .black)
    private let probe = UIView()   // the state, for the replica: identifier "player-state", label the state's name

    private var player: VLCMediaPlayer?
    private var state = PlayerState.connecting
    private var barShown = true
    private var deadline: Timer?
    private var hide: Timer?

    init(_ channel: Channel, frozen: PlayerState? = nil) {
        self.channel = channel
        self.frozen = frozen
        name = Label(channel.name, size: 18, weight: 600, color: .white, lineHeight: 28)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    override var prefersHomeIndicatorAutoHidden: Bool { state == .playing && !barShown }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .allButUpsideDown }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .black
        video.backgroundColor = .black
        video.isUserInteractionEnabled = false
        bar.backgroundColor = UIColor(white: 0, alpha: 0.6)
        back.isAccessibilityElement = true
        back.accessibilityTraits = .button
        back.accessibilityLabel = Words.back
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        back.addSubview(backIcon)
        bar.addSubview(back)
        bar.addSubview(name)
        probe.isAccessibilityElement = true
        probe.accessibilityIdentifier = "player-state"
        probe.alpha = 0.02
        for v in [video, bar, connecting, cross, failed, again, probe] as [UIView] { view.addSubview(v) }
        again.onTap = { [weak self] in self?.start() }
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let frozen { show(frozen) } else { start() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaInsets
        let x = safe.left, w = view.bounds.width - safe.left - safe.right
        video.frame = view.bounds
        bar.frame = CGRect(x: x, y: safe.top, width: w, height: 56)
        back.frame = CGRect(x: 4, y: 6, width: 44, height: 44)
        backIcon.frame = CGRect(x: 10, y: 10, width: 24, height: 24)
        name.frame = CGRect(x: 56, y: 14, width: w - 72, height: 28)
        let top = bar.frame.maxY
        connecting.frame = CGRect(x: x + 16, y: top + 8, width: w - 32, height: 24)
        cross.frame = CGRect(x: x + 16, y: top + 10, width: 20, height: 20)
        failed.frame = CGRect(x: x + 42, y: top + 8, width: w - 58, height: 24)
        again.frame = CGRect(x: x + 16, y: top + 44, width: again.naturalWidth, height: 44)
        probe.frame = CGRect(x: 0, y: view.bounds.height - 2, width: 2, height: 2)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded()
        })
    }

    // ---- states ----

    private func show(_ new: PlayerState) {
        state = new
        probe.accessibilityLabel = new.rawValue
        connecting.isHidden = new != .connecting
        for v in [cross, failed, again] as [UIView] { v.isHidden = new != .failed }
        video.isHidden = new != .playing
        hide?.invalidate()
        if new == .playing {
            hide = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in self?.setBar(false) }
        } else {
            setBar(true)
        }
    }

    private func setBar(_ shown: Bool) {
        barShown = shown
        bar.isHidden = !shown
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    @objc private func tapped() {
        guard state == .playing else { return }
        hide?.invalidate()
        setBar(!barShown)
    }

    // ---- playing ----

    private func start() {
        stop()
        show(.connecting)
        guard let url = address() else { show(.failed); return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let media = VLCMedia(url: url)
        media.addOption(":network-caching=1500")
        if let agent = channel.userAgent { media.addOption(":http-user-agent=\(agent)") }
        if let referrer = channel.referrer { media.addOption(":http-referrer=\(referrer)") }
        let p = VLCMediaPlayer()
        p.delegate = self
        p.drawable = video
        p.media = media
        player = p
        p.play()
        deadline = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            guard let self, self.state == .connecting else { return }
            self.stop()
            self.show(.failed)
        }
    }

    /// The channel's address; the fixture's `fixture://name` is a file of the bundled Fixture folder.
    private func address() -> URL? {
        let s = channel.url
        if s.hasPrefix("fixture://") {
            return Bundle.main.url(forResource: "Fixture", withExtension: nil)?.appendingPathComponent(String(s.dropFirst(10)))
        }
        return URL(string: s) ?? s.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:))
    }

    private func stop() {
        deadline?.invalidate()
        deadline = nil
        guard let p = player else { return }
        player = nil
        p.delegate = nil
        // VLC's stop waits for its threads: off the main thread
        DispatchQueue.global(qos: .userInitiated).async { p.stop() }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.player != nil, self.state == .connecting else { return }
            self.deadline?.invalidate()
            self.show(.playing)
        }
    }

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let p = self.player else { return }
            switch p.state {
            case .error, .ended, .stopped:
                self.stop()
                self.show(.failed)
            default:
                break
            }
        }
    }

    @objc private func close() {
        stop()
        hide?.invalidate()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        dismiss(animated: false)
    }
}
