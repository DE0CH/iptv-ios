import Foundation

/// The saved playlist: its URL as typed (UserDefaults) and its text as last loaded (Application Support), so the
/// channels are there at once on the next launch. Loading replaces both only when the new playlist has channels.
enum Store {
    private static let defaults = UserDefaults.standard
    private static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("playlist.m3u")
    }

    static var address: String {
        get { defaults.string(forKey: "url") ?? "" }
        set { defaults.set(newValue, forKey: "url") }
    }

    static func cached() -> [Channel] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return Playlist.parse(Playlist.text(data))
    }

    static func reset() {
        defaults.removeObject(forKey: "url")
        try? FileManager.default.removeItem(at: file)
    }

    static func fixtureChannels() -> [Channel] {
        guard let dir = Bundle.main.url(forResource: "Fixture", withExtension: nil),
              let data = try? Data(contentsOf: dir.appendingPathComponent("tv.m3u")) else { return [] }
        return Playlist.parse(Playlist.text(data))
    }

    enum Failure: Error { case notAddress, unreachable, empty }

    /// Fetches and reads the playlist at `typed`; answers on the main queue. A playlist with channels is saved.
    static func load(_ typed: String, done: @escaping (Result<[Channel], Failure>) -> Void) {
        guard let url = Playlist.address(typed) else { done(.failure(.notAddress)); return }
        func finish(_ data: Data?) {
            guard let data else { DispatchQueue.main.async { done(.failure(.unreachable)) }; return }
            let channels = Playlist.parse(Playlist.text(data))
            if !channels.isEmpty {
                try? data.write(to: file, options: .atomic)
                DispatchQueue.main.async { address = typed.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            DispatchQueue.main.async { done(channels.isEmpty ? .failure(.empty) : .success(channels)) }
        }
        if Flags.fixture {
            // the bundled playlist for any address; one with "broken" in it does not answer
            let dir = Bundle.main.url(forResource: "Fixture", withExtension: nil)
            let data = typed.contains("broken") ? nil : dir.flatMap { try? Data(contentsOf: $0.appendingPathComponent("tv.m3u")) }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { finish(data) }
            return
        }
        if url.isFileURL {
            DispatchQueue.global().async { finish(try? Data(contentsOf: url)) }
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        // playlist servers often refuse anything that does not look like a player
        request.setValue("VLC/3.0.20 LibVLC/3.0.20", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            finish(error == nil && (200..<300).contains(status) ? data : nil)
        }.resume()
    }
}
