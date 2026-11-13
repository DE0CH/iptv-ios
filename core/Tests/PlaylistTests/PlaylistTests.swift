import XCTest
@testable import Playlist

final class PlaylistTests: XCTestCase {
    func testAttributesAndNames() {
        let m3u = """
        #EXTM3U x-tvg-url="https://example.com/guide.xml"
        #EXTINF:-1 tvg-id="nasa" tvg-logo="https://example.com/a,b.png" group-title="Science, space",NASA TV
        https://example.com/nasa/master.m3u8
        #EXTINF:-1,CCTV-13 新闻
        http://example.com:8080/live/cctv13.ts

        #EXTINF:0 tvg-name="France 24",
        rtmp://example.com/live/f24
        """
        XCTAssertEqual(Playlist.parse(m3u), [
            Channel(name: "NASA TV", url: "https://example.com/nasa/master.m3u8"),
            Channel(name: "CCTV-13 新闻", url: "http://example.com:8080/live/cctv13.ts"),
            Channel(name: "France 24", url: "rtmp://example.com/live/f24"),
        ])
    }

    func testNameWithCommas() {
        let m3u = "#EXTINF:-1 group-title=\"A\",News, weather, sport\nhttp://example.com/1\n"
        XCTAssertEqual(Playlist.parse(m3u).first?.name, "News, weather, sport")
    }

    func testWindowsLineEndsAndByteOrderMark() {
        let m3u = "\u{FEFF}#EXTM3U\r\n#EXTINF:-1,One\r\nhttp://example.com/1\r\n#EXTINF:-1,Two\r\nhttp://example.com/2\r\n"
        XCTAssertEqual(Playlist.parse(m3u).map(\.name), ["One", "Two"])
        XCTAssertEqual(Playlist.parse(m3u).map(\.url), ["http://example.com/1", "http://example.com/2"])
    }

    func testPlayerOptions() {
        let m3u = """
        #EXTINF:-1,With options
        #EXTVLCOPT:http-user-agent=Mozilla/5.0 (X11)
        #EXTVLCOPT:http-referrer=https://example.com/
        #KODIPROP:inputstream=adaptive
        http://example.com/a.m3u8
        #EXTINF:-1,Kodi style
        http://example.com/b.ts|User-Agent=VLC%2F3.0&Referer=https://example.org/
        #EXTINF:-1,Plain
        http://example.com/c.ts
        """
        XCTAssertEqual(Playlist.parse(m3u), [
            Channel(name: "With options", url: "http://example.com/a.m3u8", userAgent: "Mozilla/5.0 (X11)", referrer: "https://example.com/"),
            Channel(name: "Kodi style", url: "http://example.com/b.ts", userAgent: "VLC/3.0", referrer: "https://example.org/"),
            Channel(name: "Plain", url: "http://example.com/c.ts"),
        ])
    }

    func testPlainListOfAddresses() {
        let list = "http://example.com/live/one.ts\n# a comment\nhttp://example.com/live/two%20hd.m3u8?token=1\nnot a stream\n"
        XCTAssertEqual(Playlist.parse(list), [
            Channel(name: "one.ts", url: "http://example.com/live/one.ts"),
            Channel(name: "two hd.m3u8", url: "http://example.com/live/two%20hd.m3u8?token=1"),
        ])
    }

    func testNothingUseful() {
        XCTAssertEqual(Playlist.parse(""), [])
        XCTAssertEqual(Playlist.parse("<html><body>Not found</body></html>"), [])
        XCTAssertEqual(Playlist.parse("#EXTM3U\n#EXTINF:-1,Orphan\n"), [])
    }

    func testTextEncodings() {
        XCTAssertEqual(Playlist.text(Data("凤凰卫视".utf8)), "凤凰卫视")
        #if canImport(Darwin)   // Foundation on Linux has no GB 18030
        XCTAssertEqual(Playlist.text(Data([0xB7, 0xEF, 0xBB, 0xCB])), "凤凰")   // 凤凰 in GBK
        #endif
    }

    func testTypedAddress() {
        XCTAssertEqual(Playlist.address("  example.com/tv.m3u \n")?.absoluteString, "https://example.com/tv.m3u")
        XCTAssertEqual(Playlist.address("http://10.0.0.2:8000/get.php?username=a&password=b&type=m3u_plus")?.absoluteString,
                       "http://10.0.0.2:8000/get.php?username=a&password=b&type=m3u_plus")
        XCTAssertNil(Playlist.address("   "))
        XCTAssertNil(Playlist.address("ftp://example.com/x"))
    }
}
