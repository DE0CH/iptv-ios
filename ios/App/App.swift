import UIKit

/// IPTV: the most minimal player for an M3U playlist. One screen takes the playlist's URL and lists its channels
/// (List.swift); a tap plays one full screen on VLC's engine (Player.swift). Both screens are UIKit drawn to the
/// numbers of Web/index.html, which `-reference` shows instead (Reference.swift) for the replica's comparison.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        if Flags.reset { Store.reset() }
        let window = UIWindow(windowScene: scene)
        if Flags.reference {
            window.rootViewController = ReferenceController()
        } else if let frozen = Flags.forcedPlayer {
            window.rootViewController = PlayerScreen(Channel(name: Forced.playerName, url: "fixture://missing.ts"), frozen: frozen)
        } else {
            window.rootViewController = ListScreen()
        }
        window.makeKeyAndVisible()
        self.window = window
    }
}

/// Launch flags, for the replica. `-reference`: the HTML page instead of the native screens. `-fixture`: the bundled
/// playlist (Fixture/tv.m3u) answers every load, no network. `-reset`: forget the saved playlist. `-state NAME`: hold
/// one state still, the same one natively and in the page: empty, loading, list, error, connecting, failed.
enum Flags {
    static let args = ProcessInfo.processInfo.arguments
    static let reference = args.contains("-reference")
    static let fixture = args.contains("-fixture")
    static let reset = args.contains("-reset")
    static let state: String? = args.firstIndex(of: "-state").flatMap { args.count > $0 + 1 ? args[$0 + 1] : nil }
    static var forcedPlayer: PlayerState? {
        switch state {
        case "connecting": return .connecting
        case "failed": return .failed
        default: return nil
        }
    }
}

/// What a held state shows; the page gets the same values as window.STATE.
struct Forced {
    static let playerName = "NASA TV"
    static let address = "https://example.com/tv.m3u"
    var url: String, text: String, bad: Bool, channels: [String]

    static var list: Forced? {
        switch Flags.state {
        case "empty": return Forced(url: "", text: Words.none, bad: false, channels: [])
        case "loading": return Forced(url: address, text: Words.loading, bad: false, channels: [])
        case "list":
            let names = Store.fixtureChannels().map(\.name)
            return Forced(url: address, text: Words.count(names.count), bad: false, channels: names)
        case "error": return Forced(url: address, text: Words.failed, bad: true, channels: [])
        default: return nil
        }
    }
}

/// Every sentence the app shows.
enum Words {
    static let label = "Playlist URL"
    static let placeholder = "https://example.com/playlist.m3u"
    static let load = "Load"
    static let none = "No playlist loaded"
    static let loading = "Loading"
    static let failed = "This playlist could not be loaded"
    static let noChannels = "No channels found in this playlist"
    static let notAddress = "This is not a playlist URL"
    static func count(_ n: Int) -> String { n == 1 ? "1 channel" : "\(n) channels" }
    static let connecting = "Connecting"
    static let didNotPlay = "This channel did not play"
    static let again = "Try again"
    static let back = "Back"
}
