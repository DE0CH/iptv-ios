import AVFoundation
import AVKit
import UIKit
import VLCKit

enum PlayerState: String { case connecting, playing, failed }

/// The player: the channel full screen on VLC's engine (VLCKit 4), which plays what IPTV playlists hold: HLS,
/// MPEG-TS over HTTP, RTMP, RTSP, UDP. Always dark, every orientation. A bar with Back and the channel's name sits
/// at the top; while the channel plays it also holds the picture-in-picture button, hides after 3 seconds, and a tap
/// shows or hides it. A channel that does not start within 20 seconds, errors or ends shows "This channel did not
/// play" with Try again.
///
/// Picture in picture is VLCKit's: the drawable (`Picture`) tells VLC it can do it, VLC hands back a controller once
/// its display is up, and the button asks that controller to start. Leaving the app without picture in picture, or
/// closing the small picture while the app is in the background, stops the channel; it starts again on return.
final class PlayerScreen: UIViewController, VLCMediaPlayerDelegate {
    private let channel: Channel
    private let frozen: PlayerState?   // the replica's held state: nothing is played
    private let video = UIView()
    private let touch = UIControl()
    private let bar = UIView()
    private let back = UIControl()
    private let pipButton = UIControl()
    private let pipIcon = IconView(Icon.pip, size: 24, tint: .white)
    private let picture = Picture()
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
    private var inPicture = false    // the small picture is up
    private var suspended = false    // stopped because the app left the screen; starts again on return

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
        pipButton.isAccessibilityElement = true
        pipButton.accessibilityTraits = .button
        pipButton.accessibilityLabel = Words.pip
        pipButton.addTarget(self, action: #selector(startPicture), for: .touchUpInside)
        pipButton.addSubview(pipIcon)
        pipButton.isHidden = true
        bar.addSubview(back)
        bar.addSubview(name)
        bar.addSubview(pipButton)
        picture.host = video
        picture.onReady = { [weak self] in self?.pictureChanged() }
        picture.onState = { [weak self] started in self?.pictureStarted(started) }
        probe.isAccessibilityElement = true
        probe.accessibilityIdentifier = "player-state"
        probe.alpha = 0.02
        // a control over the whole picture takes the tap that shows or hides the bar (VLC's own view sits in `video`)
        touch.accessibilityIdentifier = "picture"
        touch.isAccessibilityElement = true
        touch.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        for v in [video, touch, bar, connecting, cross, failed, again, probe] as [UIView] { view.addSubview(v) }
        again.onTap = { [weak self] in self?.start() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if let frozen { show(frozen); return }
        start()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(left), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(returned), name: UIApplication.willEnterForegroundNotification, object: nil)
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
        touch.frame = view.bounds
        bar.frame = CGRect(x: x, y: safe.top, width: w, height: 56)
        back.frame = CGRect(x: 4, y: 6, width: 44, height: 44)
        backIcon.frame = CGRect(x: 10, y: 10, width: 24, height: 24)
        pipButton.frame = CGRect(x: w - 48, y: 6, width: 44, height: 44)
        pipIcon.frame = CGRect(x: 10, y: 10, width: 24, height: 24)
        name.frame = CGRect(x: 56, y: 14, width: w - 72 - (pipButton.isHidden ? 0 : 40), height: 28)
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
        pictureChanged()
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

    // ---- picture in picture ----

    /// The button is there while the channel plays, the phone can do picture in picture and VLC's display is ready.
    private func pictureChanged() {
        let supported = AVPictureInPictureController.isPictureInPictureSupported()
        let can = state == .playing && picture.controller != nil && supported
        // for the replica: why the button is or is not there
        probe.accessibilityValue = "pip device \(supported ? "can" : "cannot"), vlc \(picture.controller != nil ? "ready" : "not ready")"
        guard pipButton.isHidden == can else { return }
        pipButton.isHidden = !can
        view.setNeedsLayout()
    }

    @objc private func startPicture() {
        picture.controller?.startPictureInPicture()
    }

    private func pictureStarted(_ started: Bool) {
        inPicture = started
        guard !started else { return }
        // the small picture was closed: back in the app the channel plays on; in the background it stops
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, !self.inPicture, UIApplication.shared.applicationState == .background else { return }
            self.suspend()
        }
    }

    private func suspend() {
        guard player != nil else { return }
        suspended = true
        stop()
    }

    @objc private func left() {
        if !inPicture { suspend() }
    }

    @objc private func returned() {
        guard suspended else { return }
        suspended = false
        start()
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
        guard let media = VLCMedia(url: url) else { show(.failed); return }
        media.addOption(":network-caching=1500")
        if let agent = channel.userAgent { media.addOption(":http-user-agent=\(agent)") }
        if let referrer = channel.referrer { media.addOption(":http-referrer=\(referrer)") }
        let p = VLCMediaPlayer()
        p.delegate = self
        p.drawable = picture
        picture.player = p
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
        if inPicture { picture.controller?.stopPictureInPicture() }
        picture.controller = nil
        picture.player = nil
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

    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.player != nil else { return }
            self.picture.controller?.invalidatePlaybackState()
            // a stream that ends goes to stopped
            if newState == .error || newState == .stopped {
                self.stop()
                self.show(.failed)
            }
        }
    }

    @objc private func close() {
        NotificationCenter.default.removeObserver(self)
        stop()
        hide?.invalidate()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        dismiss(animated: false)
    }
}

/// What VLC draws into, and what its picture in picture asks about the channel. VLC adds its display view to `host`
/// and, once that display can do picture in picture, hands over the controller that starts and stops it.
final class Picture: NSObject, VLCDrawable, VLCPictureInPictureDrawable, VLCPictureInPictureMediaControlling {
    weak var host: UIView?
    weak var player: VLCMediaPlayer?
    var controller: VLCPictureInPictureWindowControlling?
    var onReady: (() -> Void)?
    var onState: ((Bool) -> Void)?

    func addSubview(_ view: UIView!) {
        guard let view, let host else { return }
        view.isUserInteractionEnabled = false
        host.addSubview(view)
    }

    func bounds() -> CGRect { host?.bounds ?? .zero }

    func mediaController() -> VLCPictureInPictureMediaControlling! { self }

    func pictureInPictureReady() -> ((VLCPictureInPictureWindowControlling?) -> Void)! {
        return { [weak self] controller in
            DispatchQueue.main.async {
                guard let self else { return }
                self.controller = controller
                controller?.stateChangeEventHandler = { [weak self] started in
                    DispatchQueue.main.async { self?.onState?(started) }
                }
                self.onReady?()
            }
        }
    }

    func play() { player?.play() }
    func pause() { player?.pause() }
    func seek(by offset: Int64, completion: (() -> Void)!) { completion?() }   // live television: nothing to seek
    func mediaLength() -> Int64 { 0 }
    func mediaTime() -> Int64 { player?.time.value?.int64Value ?? 0 }
    func isMediaSeekable() -> Bool { false }
    func isMediaPlaying() -> Bool { player?.isPlaying ?? false }
}
