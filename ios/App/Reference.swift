import UIKit
import WebKit

/// `-reference`: Web/index.html in a WKWebView, the page the native screens are drawn from, holding the state the
/// `-state` flag names (given to the page as window.STATE). The replica compares the two screen by screen.
final class ReferenceController: UIViewController {
    private var player: Bool { Flags.forcedPlayer != nil }
    override var preferredStatusBarStyle: UIStatusBarStyle { player ? .lightContent : .default }

    override func loadView() {
        var state: [String: Any]
        if let p = Flags.forcedPlayer {
            state = ["screen": "player", "name": Forced.playerName, "player": p.rawValue]
        } else {
            let f = Forced.list ?? Forced(url: "", text: Words.none, bad: false, channels: [])
            state = ["screen": "list", "url": f.url, "status": f.bad ? "bad" : "none", "text": f.text, "channels": f.channels]
        }
        let json = String(data: (try? JSONSerialization.data(withJSONObject: state)) ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addUserScript(WKUserScript(source: "window.STATE = \(json);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let web = WKWebView(frame: .zero, configuration: config)
        let ground: UIColor = player ? .black : .ground
        web.isOpaque = false
        web.backgroundColor = ground
        web.underPageBackgroundColor = ground
        web.scrollView.backgroundColor = ground
        web.scrollView.showsVerticalScrollIndicator = false
        if let dir = Bundle.main.url(forResource: "Web", withExtension: nil) {
            web.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
        }
        view = web
    }
}
