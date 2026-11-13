# IPTV

A minimal iPhone player for M3U IPTV playlists. Type the playlist's URL, tap Load, tap a channel.

- **Two screens.** The list: the playlist URL, Load, a status line and the channels in the playlist's order. The
  player: the channel full screen, in any orientation, with a bar (Back, the channel's name) that hides after 3
  seconds of playing and comes back on a tap. Nothing else: no groups, search, favourites or programme guide.
- **Playlist** (`core/Sources/Playlist/Playlist.swift`): `#EXTINF` names (text after the first comma outside quotes,
  else `tvg-name`, else the URL's last part), `#EXTVLCOPT:http-user-agent` / `http-referrer`, Kodi's
  `URL|User-Agent=…&Referer=…`, plain lists of URLs; UTF-8, else GB 18030, else Latin-1. The URL and the playlist's
  text are kept on the phone (UserDefaults, Application Support), so the channels are there at the next launch; Load
  fetches it again. A failed load leaves the channels already shown.
- **Playback** (`ios/App/Player.swift`): VLC's engine, [MobileVLCKit](https://code.videolan.org/videolan/VLCKit) 3.6.0
  (LGPL 2.1, VideoLAN's own binary, fetched by `ios/vlckit.sh` and embedded as a dynamic framework), so HLS, MPEG-TS
  over HTTP, RTMP, RTSP and UDP streams play. A channel that does not start within 20 seconds, errors or ends shows
  "This channel did not play" with Try again.
- **Screens are UIKit drawn to a page.** `ios/App/Web/index.html` is the layout (open it in a browser with `#empty`,
  `#loading`, `#list`, `#error`, `#connecting`, `#failed`, `#playing`); `List.swift` and `Player.swift` place every
  piece by hand to its numbers, text as Core Text lines at WebKit's baselines (`Style.swift`). The launch flag
  `-reference` shows the page instead, and the replica compares the two pixel by pixel.
- **Launch flags** (for the replica): `-fixture` (the bundled `Fixture/tv.m3u` answers every load; "Test card" plays
  the bundled clip, "No signal" is a missing file; a URL containing "broken" fails), `-reset`, `-state NAME` (hold one
  state still), `-reference`.

## Build

`.github/workflows/ios.yml`, on every push to `main`: the parser's tests on Linux (`core/`, `swift test`), then on a
macOS runner the phone replica on an iPhone 17 simulator (`ios/UITests`: every flow on the fixture, a live public
playlist reported but not gating, each state against the page with at most 0.5% of pixels differing), an unsigned
archive, and a cloud-signed export to TestFlight (App Store Connect API key in the repo secrets `ASC_KEY_ID`,
`ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`). Bundle id `dev.de0ch.iptv`.

Locally: `cd ios && ./vlckit.sh && xcodegen generate && open IPTV.xcodeproj`.
