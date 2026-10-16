#if DEBUG
import Foundation
import MorningCore
import WebKit

/// A closed document input for the ordinary browser executor, never an executor.
/// No disk paths, HTTP client, credentials, redirects or fallback are available.
@MainActor final class SyntheticNewsSchemeHandler: NSObject, WKURLSchemeHandler {
    let origin: SyntheticNewsOrigin
    private let french: Bool
    private(set) var deliveredHTML: Set<URL> = []
    private(set) var deliveryCount = 0
    init(origin: SyntheticNewsOrigin, french: Bool) { self.origin = origin; self.french = french }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let request = urlSchemeTask.request
        guard request.httpMethod == "GET", request.httpBody == nil, let url = request.url,
              origin.permits(url), let html = document(path: url.path) else {
            urlSchemeTask.didFailWithError(URLError(.resourceUnavailable)); return
        }
        let data = Data(html.utf8)
        // This is a local URLResponse, deliberately not an invented HTTP 200.
        urlSchemeTask.didReceive(URLResponse(url: url, mimeType: "text/html", expectedContentLength: data.count, textEncodingName: "utf-8"))
        urlSchemeTask.didReceive(data)
        deliveredHTML.insert(url)
        deliveryCount += 1
        urlSchemeTask.didFinish()
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    private func document(path: String) -> String? {
        let titles = french ? ["La serre accueille des semis", "Un coin lecture au jardin Cèdre", "Le club dessine des cartes"]
            : ["Greenhouse welcomes seedlings", "A reading corner at Cedar garden", "The club draws maps"]
        let content: String
        if path == "/headlines" {
            content = zip(Array(SyntheticNewsOrigin.paths.dropFirst()), titles).map { path, title in
                "<article><a href=\"\(path)\"><h2>\(title)</h2></a></article>"
            }.joined()
        } else if let index = SyntheticNewsOrigin.paths.dropFirst().firstIndex(of: path) {
            let title = titles[index - 1]
            let paragraph: String
            if path == "/article/two" {
                paragraph = french
                    ? "Le jardin Cèdre ouvre un coin lecture samedi. Des bénévoles ont placé six bancs près des érables. Les inscriptions sont gratuites et se font sur place. Le chantier a utilisé du bois récupéré dans l’atelier voisin. La bibliothèque prêtera des livres aux visiteurs. Ce récit est entièrement inventé pour le test SYNTHETIC."
                    : "Cedar garden opens a reading corner on Saturday. Volunteers placed six benches beside the maples. Registration is free and takes place on site. The project used wood recovered from the nearby workshop. The library will lend books to visitors. This story is entirely invented for the SYNTHETIC test."
            } else {
                paragraph = french ? "SYNTHETIC : autre article inventé, distinct du deuxième article choisi."
                    : "SYNTHETIC: another invented article, distinct from the selected second article."
            }
            content = "<article itemprop=\"articleBody\"><h1>\(title)</h1><p>\(paragraph)</p></article>"
        } else { return nil }
        return """
        <!doctype html><html lang="\(french ? "fr" : "en")"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; connect-src 'none'; form-action 'none'; frame-src 'none'; base-uri 'none'">
        <title>SYNTHETIC Cedar News</title>
        <style>body{font:18px system-ui;margin:16px;background:#fff;color:#171717}header{font-weight:bold}article{margin:12px 0}h1,h2{font-size:20px}p{line-height:1.6}a{color:#164b80}</style></head>
        <body><header>SYNTHETIC · Cedar News · \(french ? "FR" : "EN")</header><main>\(content)</main></body></html>
        """
    }
}
#endif
