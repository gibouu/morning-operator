#if DEBUG
import Foundation
import MorningCore
import WebKit

/// Closed synthetic pages only. All navigation, playback, observation and
/// progression still go through WebMorningController's ordinary executor.
@MainActor final class SyntheticRoutineBrowserSchemeHandler: NSObject, WKURLSchemeHandler {
    static let mediaPrefix = "--ui-testing-private-browser-media="
    let origin: SyntheticRoutineBrowserOrigin
    private let video: Data
    private let music: Data
    private(set) var delivered = Set<URL>()
    private(set) var deliveryCount = 0

    init?(origin: SyntheticRoutineBrowserOrigin, arguments: [String]) {
        let values = arguments.filter { $0.hasPrefix(Self.mediaPrefix) }
        guard values.count == 1, values[0].utf8.count <= 360_000,
              let input = Data(base64Encoded: String(values[0].dropFirst(Self.mediaPrefix.count))),
              input.count <= 260_000,
              let assets = try? JSONDecoder().decode([String: Data].self, from: input),
              Set(assets.keys) == ["video", "music"],
              let video = assets["video"], (20...120_000).contains(video.count),
              video.dropFirst(4).prefix(4) == Data("ftyp".utf8),
              let music = assets["music"], (44...120_000).contains(music.count),
              music.prefix(4) == Data("RIFF".utf8), music.dropFirst(8).prefix(4) == Data("WAVE".utf8) else { return nil }
        self.origin = origin; self.video = video; self.music = music
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let request = task.request
        guard request.httpMethod == "GET", request.httpBody == nil, let url = request.url, origin.permits(url) else {
            task.didFailWithError(URLError(.resourceUnavailable)); return
        }
        let data = Data(document().utf8)
        task.didReceive(URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
        task.didReceive(data); delivered.insert(url); deliveryCount += 1; task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func document() -> String {
        let french = AppLanguage.isFrench
        let content: String
        let script: String
        if origin.site == .reddit {
            let posts = french
                ? ["Six cartes pour le jardin", "La serre ouvre samedi", "Une promenade près du canal", "Le coin lecture du quartier", "Fin du fil inventé"]
                : ["Six cards for the garden", "The greenhouse opens Saturday", "A walk beside the canal", "The neighbourhood reading corner", "End of the invented feed"]
            content = posts.enumerated().map { index, title in
                "<article data-testid=\"post-container\" data-id=\"synthetic-post-\(index + 1)\"><h2>\(title)</h2><p>SYNTHETIC · \(french ? "Publication inventée" : "Invented post") \(index + 1)</p></article>"
            }.joined()
            script = ""
        } else if origin.isMusic {
            content = "<h2>\(french ? "Lumière sur le jardin" : "Light in the garden") · SYNTHETIC</h2><video id=\"synthetic-music\" controls playsinline loop src=\"data:audio/wav;base64,\(music.base64EncodedString())\">SYNTHETIC generated garden melody</video>"
            script = ""
        } else {
            content = (1...2).map { index in
                "<section\(index == 2 ? " hidden" : "") data-item=\"\(index)\"><h2>SYNTHETIC \(french ? "Vidéo" : "Video") \(index)</h2><video id=\"synthetic-video-\(index)\" controls playsinline muted loop src=\"data:video/mp4;base64,\(video.base64EncodedString())\">SYNTHETIC generated video \(index)</video></section>"
            }.joined() + "<button id=\"next\" aria-label=\"next video\">\(french ? "Vidéo suivante" : "Next video")</button>"
            script = "document.getElementById('next').addEventListener('click',()=>{document.querySelector('[data-item=\"1\"] video').pause();document.querySelector('[data-item=\"1\"]').hidden=true;document.querySelector('[data-item=\"2\"]').hidden=false;document.getElementById('next').hidden=true;});"
        }
        return """
        <!doctype html><html lang="\(french ? "fr" : "en")"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; media-src data:; connect-src 'none'; form-action 'none'; frame-src 'none'; base-uri 'none'">
        <title>SYNTHETIC Cedar \(origin.site == .reddit ? "Social" : origin.isMusic ? "Music" : "Video")</title>
        <style>body{font:18px system-ui;margin:16px;background:#fff;color:#171717}header{font-weight:bold}article{height:560px;padding:12px;border-bottom:1px solid #ccc}video{width:100%;height:300px;background:#264d40}button{font:inherit;padding:14px}[hidden]{display:none!important}</style>
        </head><body><header>SYNTHETIC · \(french ? "Routine inventée, aucun compte connecté" : "Invented routine, no connected account")</header><main>\(content)</main><script>\(script)</script></body></html>
        """
    }
}
#endif
