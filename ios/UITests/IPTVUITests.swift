import XCTest

/// The phone replica: every flow on the simulator with the bundled playlist and test clip (-fixture), a live playlist
/// from the internet (reported, not gating), then each native screen against the page it is drawn from (-reference).
final class IPTVUITests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    private func texts(_ app: XCUIApplication) -> String { app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label).joined(separator: " | ") }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// The player's state ("connecting", "playing", "failed") once it is `want`, or whatever it is after `seconds`.
    private func player(_ app: XCUIApplication, _ want: String, _ seconds: TimeInterval) -> String {
        let probe = app.descendants(matching: .any)["player-state"].firstMatch
        let end = Date().addingTimeInterval(seconds)
        var last = "no player"
        while Date() < end {
            if probe.exists { last = probe.label; if last == want { return last } }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return last
    }

    private func type(_ app: XCUIApplication, _ text: String) {
        let field = app.textFields["Playlist URL"]
        field.tap()
        field.typeText(text)
    }

    /// Every flow on the fixture: load a playlist, play a channel, turn the phone, the bar hiding and coming back,
    /// a channel that fails, a playlist that fails, and the playlist remembered across a relaunch.
    func testEveryFlow() throws {
        XCUIDevice.shared.orientation = .portrait
        var app = launch(["-fixture", "-reset"])
        XCTAssertTrue(app.staticTexts["No playlist loaded"].waitForExistence(timeout: 20), texts(app))
        shot("flow-empty")

        type(app, "example.com/tv.m3u")
        app.buttons["Load"].tap()
        XCTAssertTrue(app.staticTexts["12 channels"].waitForExistence(timeout: 10), texts(app))
        XCTAssertTrue(app.staticTexts["Test card"].exists, texts(app))
        XCTAssertTrue(app.staticTexts["CCTV-13 新闻"].exists, texts(app))
        shot("flow-list")

        // a channel plays (the bundled MPEG-TS clip, through VLC)
        app.staticTexts["Test card"].tap()
        XCTAssertEqual(player(app, "playing", 40), "playing")
        shot("flow-playing")
        // picture in picture: the button is there where the device can do it (reported; a simulator may not)
        let pip = app.buttons["Picture in picture"]
        Thread.sleep(forTimeInterval: 1)
        let why = app.descendants(matching: .any)["player-state"].firstMatch.value as? String ?? "?"
        print("PIP button: \(pip.exists ? "shown" : "not shown") (\(why))")
        if pip.exists {
            pip.tap()
            Thread.sleep(forTimeInterval: 3)
            shot("flow-picture-in-picture")
            print("PIP after the tap: player \(player(app, "playing", 5))")
            app.activate()
        }
        print("ROTATE flow landscape \(Date().timeIntervalSince1970)")
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        shot("flow-playing-landscape")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 3)
        // the bar has hidden itself; a tap brings it back
        XCTAssertFalse(app.buttons["Back"].exists, "the bar did not hide")
        app.descendants(matching: .any)["picture"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 3), "the bar did not come back")
        XCTAssertEqual(player(app, "playing", 5), "playing")
        shot("flow-playing-bar")
        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["12 channels"].waitForExistence(timeout: 5), texts(app))

        // a channel that is not there
        app.staticTexts["No signal"].tap()
        XCTAssertEqual(player(app, "failed", 30), "failed")
        XCTAssertTrue(app.staticTexts["This channel did not play"].exists, texts(app))
        shot("flow-failed")
        app.buttons["Try again"].tap()
        XCTAssertEqual(player(app, "failed", 30), "failed")
        app.buttons["Back"].tap()

        // a playlist that does not answer: the error shows, the channels stay
        type(app, "broken")
        app.buttons["Load"].tap()
        XCTAssertTrue(app.staticTexts["This playlist could not be loaded"].waitForExistence(timeout: 10), texts(app))
        XCTAssertTrue(app.staticTexts["Test card"].exists, texts(app))
        shot("flow-playlist-failed")

        app.terminate()
        app = launch(["-fixture"])
        XCTAssertTrue(app.staticTexts["12 channels"].waitForExistence(timeout: 20), "playlist not remembered: \(texts(app))")
        XCTAssertEqual(app.textFields["Playlist URL"].value as? String, "example.com/tv.m3u")
        app.terminate()
    }

    /// The real thing: a public playlist over the network and its first channel. Reported, not gating: the
    /// playlist's host or the channel may not answer a CI runner.
    func testLive() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(["-reset"])
        _ = app.staticTexts["No playlist loaded"].waitForExistence(timeout: 20)
        type(app, "https://iptv-org.github.io/iptv/countries/hk.m3u")
        let started = Date()
        app.buttons["Load"].tap()
        let count = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' channels'")).firstMatch
        let loaded = count.waitForExistence(timeout: 60)
        print("LIVE playlist: \(loaded ? count.label : "no answer in 60 s") after \(String(format: "%.1f", Date().timeIntervalSince(started))) s | \(texts(app))")
        shot("live-list")
        if loaded {
            // the first channels in turn until one plays: any one of them may be off the air or closed to the runner
            var results: [String] = []
            for i in 0..<min(5, app.cells.count) {
                let cell = app.cells.element(boundBy: i)
                let name = cell.staticTexts.firstMatch.label
                cell.tap()
                let state = player(app, "playing", 25)
                results.append("\(name): \(state)")
                if state == "playing" { Thread.sleep(forTimeInterval: 2); shot("live-player") }
                app.buttons["Back"].tap()
                _ = count.waitForExistence(timeout: 5)
                if state == "playing" { break }
            }
            print("LIVE channels: \(results.joined(separator: "; "))")
        }
        app.terminate()
    }

    /// The native screens against the page (`-reference`), state by state. Prints the share of differing pixels and
    /// attaches native/html/diff images.
    func testMatchesReference() throws {
        let states: [(name: String, state: String, landscape: Bool)] = [
            ("empty", "empty", false), ("loading", "loading", false), ("list", "list", false), ("error", "error", false),
            ("connecting", "connecting", false), ("failed", "failed", false),
            ("list-landscape", "list", true), ("failed-landscape", "failed", true),
        ]
        for s in states {
            var pair: [String: XCUIScreenshot] = [:]
            for mode in ["native", "html"] {
                XCUIDevice.shared.orientation = .portrait
                let app = launch(["-fixture", "-reset", "-state", s.state] + (mode == "html" ? ["-reference"] : []))
                if s.landscape {
                    print("ROTATE \(mode) landscape \(Date().timeIntervalSince1970)")
                    XCUIDevice.shared.orientation = .landscapeLeft
                }
                // the page may take a while the first time WebKit starts: wait for its text, then let it settle
                let mark = s.state == "connecting" || s.state == "failed" ? "NASA TV" : "Playlist URL"
                XCTAssertTrue(app.staticTexts[mark].waitForExistence(timeout: 30), "\(s.name) \(mode): \(texts(app))")
                Thread.sleep(forTimeInterval: 2)
                pair[mode] = XCUIScreen.main.screenshot()
                app.terminate()
            }
            XCUIDevice.shared.orientation = .portrait
            compare(s.name, pair["native"]!, pair["html"]!)
        }
    }

    private func compare(_ name: String, _ native: XCUIScreenshot, _ html: XCUIScreenshot) {
        let a = Gray(native.image), b = Gray(html.image)
        guard a.width == b.width, a.height == b.height else { XCTFail("\(name): sizes differ"); return }
        var differ = 0
        var diff = [UInt8](repeating: 0, count: a.width * a.height * 4)
        for i in 0..<(a.width * a.height) {
            let (x, y) = (Int(a.pixels[i]), Int(b.pixels[i]))
            let same = abs(x - y) <= 60
            if !same { differ += 1 }
            // same: faded; only in the native screen: red; only in the HTML: blue
            let v = UInt8(min(255, 170 + x / 3))
            diff[i * 4 + 0] = same ? v : (x < y ? 230 : 30)
            diff[i * 4 + 1] = same ? v : 30
            diff[i * 4 + 2] = same ? v : (x < y ? 30 : 230)
            diff[i * 4 + 3] = 255
        }
        let share = Double(differ) / Double(a.width * a.height)
        // where: the bands of rows (in points from the top) with differing pixels, so a failure reads from the log alone
        var bands: [(Int, Int)] = [], scale = max(1, a.width / 400)
        for y in 0..<a.height {
            var n = 0
            for x in 0..<a.width where abs(Int(a.pixels[y * a.width + x]) - Int(b.pixels[y * a.width + x])) > 60 { n += 1 }
            guard n > 2 else { continue }
            if let last = bands.last, y - last.1 <= 4 * scale { bands[bands.count - 1].1 = y } else { bands.append((y, y)) }
        }
        let where_ = bands.prefix(12).map { "\($0.0 / scale)-\($0.1 / scale)" }.joined(separator: " ")
        print("COMPARE \(name): differing \(String(format: "%.4f", share * 100))% at y \(where_)")
        for (label, image) in [("native", native.image), ("html", html.image), ("diff", Gray.image(diff, a.width, a.height))] {
            let attachment = XCTAttachment(image: image)
            attachment.name = "cmp-\(name)-\(label)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertLessThan(share, Self.maxDiffer, "\(name): \(share * 100)% of pixels differ")
    }

    /// The share of pixels allowed to differ between the native screen and the page.
    static let maxDiffer = 0.005
}

/// A screenshot as 8-bit grey pixels.
private struct Gray {
    let width: Int, height: Int
    var pixels: [UInt8]

    init(_ image: UIImage) {
        let cg = image.cgImage!
        width = cg.width; height = cg.height
        pixels = [UInt8](repeating: 0, count: width * height)
        let (w, h) = (width, height)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
    }

    static func image(_ rgba: [UInt8], _ width: Int, _ height: Int) -> UIImage {
        var data = rgba
        let cg = data.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!.makeImage()!
        }
        return UIImage(cgImage: cg)
    }
}
