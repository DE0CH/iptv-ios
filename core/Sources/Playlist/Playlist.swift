import Foundation

/// One entry of an M3U playlist: what to show, what to play, and what the player must send to get it.
struct Channel: Equatable {
    var name: String
    var url: String
    var userAgent: String? = nil
    var referrer: String? = nil
}

/// An M3U / M3U8 IPTV playlist as the common players read it:
///
///     #EXTM3U
///     #EXTINF:-1 tvg-id="x" tvg-logo="…" group-title="News",Channel name
///     #EXTVLCOPT:http-user-agent=Mozilla/5.0
///     #EXTVLCOPT:http-referrer=https://example.com/
///     http://host/stream.ts|User-Agent=…&Referer=…
///
/// A channel is every line that is not a comment; its name is the text after the first comma outside quotes of the
/// #EXTINF line before it (or the `tvg-name` attribute when that is empty, or the URL's last part). A plain list of
/// URLs with no #EXTINF lines is a playlist too.
enum Playlist {
    static func parse(_ text: String) -> [Channel] {
        var out: [Channel] = []
        var name: String?, agent: String?, referrer: String?
        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            let line = raw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                let upper = line.uppercased()
                if upper.hasPrefix("#EXTINF:") {
                    name = title(String(line.dropFirst(8)))
                    agent = nil
                    referrer = nil
                } else if upper.hasPrefix("#EXTVLCOPT:") {
                    let option = String(line.dropFirst(11))
                    if let v = value(option, "http-user-agent") { agent = v }
                    if let v = value(option, "http-referrer") ?? value(option, "http-referer") { referrer = v }
                }
                continue
            }
            // Kodi style: URL|User-Agent=…&Referer=…
            var url = line
            if let bar = line.firstIndex(of: "|"), line.contains("://") {
                url = String(line[..<bar])
                for pair in line[line.index(after: bar)...].split(separator: "&") {
                    guard let eq = pair.firstIndex(of: "=") else { continue }
                    let key = pair[..<eq].lowercased()
                    let v = String(pair[pair.index(after: eq)...])
                    let decoded = v.removingPercentEncoding ?? v
                    if key == "user-agent" { agent = decoded }
                    if key == "referer" || key == "referrer" { referrer = decoded }
                }
            }
            guard url.contains("://") || url.hasPrefix("/") else { name = nil; agent = nil; referrer = nil; continue }
            let shown = (name?.isEmpty == false ? name : nil) ?? fallbackName(url)
            out.append(Channel(name: shown, url: url, userAgent: agent, referrer: referrer))
            name = nil
            agent = nil
            referrer = nil
        }
        return out
    }

    /// The playlist's bytes as text: UTF-8 (the standard), else GB 18030 (older Chinese lists), else Latin-1, which
    /// never fails.
    static func text(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        let gb = String.Encoding(rawValue: 0x8000_0632)   // GB 18030, as an NSStringEncoding
        if let s = String(data: data, encoding: gb) { return s }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// What the user typed as a URL: trimmed, with https:// in front of a bare host.
    static func address(_ typed: String) -> URL? {
        var s = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s) ?? s.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap(URL.init(string:)),
              let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) else { return nil }
        return url
    }

    /// The part of an #EXTINF line after its duration and attributes: the text after the first comma outside quotes.
    /// An empty one falls back to tvg-name.
    private static func title(_ info: String) -> String {
        var quoted = false
        var comma: String.Index?
        for i in info.indices {
            let c = info[i]
            if c == "\"" { quoted.toggle() } else if c == "," && !quoted { comma = i; break }
        }
        // a line with an unclosed quote: take the last comma
        if comma == nil { comma = info.lastIndex(of: ",") }
        let name = comma.map { info[info.index(after: $0)...].trimmingCharacters(in: .whitespaces) } ?? ""
        if !name.isEmpty { return name }
        return attribute(info, "tvg-name") ?? ""
    }

    private static func attribute(_ info: String, _ key: String) -> String? {
        guard let r = info.range(of: key + "=\"", options: .caseInsensitive) else { return nil }
        let rest = info[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let v = rest[..<end].trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }

    private static func value(_ option: String, _ key: String) -> String? {
        guard let eq = option.firstIndex(of: "="), option[..<eq].trimmingCharacters(in: .whitespaces).lowercased() == key else { return nil }
        let v = option[option.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }

    private static func fallbackName(_ url: String) -> String {
        let path = url.split(separator: "?").first.map(String.init) ?? url
        let last = path.split(separator: "/").last.map(String.init) ?? url
        return last.removingPercentEncoding ?? last
    }
}
