import UIKit
import WebKit

/// `mypad write`: Markdown, HTML or SVG rendered once by WebKit into a PNG reference. Main thread only.
enum WriteRenderer {
    /// `marked.min.js` ships as an app resource; tests point this at the repository copy.
    static var markedURL: URL? = Bundle.main.url(forResource: "marked.min", withExtension: "js")
    static let baseURL = URL(string: "https://mypad.local/")
    static let pixelLimit: CGFloat = 20_000_000
    static let maxScale: CGFloat = 4
    /// Offscreen web views are attached here (set by the board) so WebKit paints them.
    static weak var hostView: UIView?
    private static var jobs: [ObjectIdentifier: Job] = [:]

    private static let css = """
    :root { color-scheme: light; }
    html, body { margin: 0; background: transparent; }
    body { font: 17px/1.55 -apple-system, system-ui, sans-serif; color: #1d2330; -webkit-text-size-adjust: 100%; }
    #page { box-sizing: border-box; width: 100%; overflow-wrap: anywhere; }
    #page > :first-child { margin-top: 0; } #page > :last-child { margin-bottom: 0; }
    h1, h2, h3, h4 { line-height: 1.22; margin: 1.3em 0 .5em; }
    h1 { font-size: 30px; } h2 { font-size: 24px; } h3 { font-size: 20px; } h4 { font-size: 17px; }
    p, ul, ol, pre, table, blockquote { margin: 0 0 1em; }
    ul, ol { padding-left: 1.4em; } li { margin: .2em 0; }
    code { font: 14.5px ui-monospace, Menlo, monospace; background: #f1f3f6; padding: .1em .35em; border-radius: 5px; }
    pre { background: #f4f5f8; padding: 14px 16px; border-radius: 12px; white-space: pre-wrap; }
    pre code { background: none; padding: 0; font-size: 14px; line-height: 1.5; }
    blockquote { padding: .1em 1em; border-left: 4px solid #d5dae3; color: #4a5365; }
    table { border-collapse: collapse; width: 100%; font-size: 15.5px; }
    th, td { border: 1px solid #dfe3ea; padding: 7px 11px; text-align: left; vertical-align: top; }
    th { background: #f4f5f8; }
    img, svg { max-width: 100%; height: auto; display: block; }
    hr { border: 0; border-top: 1px solid #dfe3ea; margin: 1.5em 0; }
    """

    /// Everything is drawn straight on the board, no sheet behind it. Full HTML documents are used as written.
    static func page(source: String, format: String) throws -> String {
        let head = "<!doctype html><html><head><meta charset=\"utf-8\">"
            + "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><style>\(css)</style></head><body>"
        switch format {
        case "html":
            let start = source.prefix(400).lowercased()
            if start.contains("<!doctype") || start.contains("<html") { return source }
            return head + "<main id=\"page\">\(source)</main></body></html>"
        case "svg":
            return head + "<main id=\"page\">\(source)</main></body></html>"
        default:
            guard let url = markedURL, let library = try? String(contentsOf: url, encoding: .utf8) else {
                throw BridgeFailure("Markdown renderer is missing from the app", code: "render_failed")
            }
            // JSON string with "<" escaped so source text can never close the script element.
            let data = try JSONSerialization.data(withJSONObject: [source])
            let literal = String(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003c").dropFirst().dropLast())
            return head + "<main id=\"page\"></main><script>\(library)</script>"
                + "<script>document.getElementById('page').innerHTML = marked.parse(\(literal), {gfm: true});</script></body></html>"
        }
    }

    /// Largest scale up to 4x board points that keeps the PNG within the 20M-pixel image limit.
    static func rasterSize(for size: CGSize) -> CGSize {
        let scale = max(1, min(maxScale, (pixelLimit / max(1, size.width * size.height)).squareRoot()))
        return CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
    }

    /// Renders `source` at `width` board points; the result is a PNG and its height in board points.
    static func render(source: String, format: String, width: CGFloat,
                       done: @escaping (Result<(png: Data, height: CGFloat), Error>) -> Void) {
        let job = Job(source: source, format: format, width: width, done: done)
        jobs[ObjectIdentifier(job)] = job
        job.start()
    }

    private final class Host: NSObject, WKNavigationDelegate {
        var onFinish: (() -> Void)?
        var onFail: ((Error) -> Void)?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onFinish?() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFail?(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onFail?(error) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onFail?(BridgeFailure("The web content process ended", code: "render_failed"))
        }
    }

    private final class Job {
        let source: String, format: String, width: CGFloat
        var done: ((Result<(png: Data, height: CGFloat), Error>) -> Void)?
        var web: WKWebView?
        let host = Host()

        init(source: String, format: String, width: CGFloat, done: @escaping (Result<(png: Data, height: CGFloat), Error>) -> Void) {
            self.source = source; self.format = format; self.width = width; self.done = done
        }

        func start() {
            let page: String
            do { page = try WriteRenderer.page(source: source, format: format) } catch { return finish(.failure(error)) }
            let web = WKWebView(frame: CGRect(x: -width - 200, y: 0, width: width, height: 800), configuration: WKWebViewConfiguration())
            web.isOpaque = false
            web.backgroundColor = .clear
            web.scrollView.backgroundColor = .clear
            web.scrollView.isScrollEnabled = false
            web.isUserInteractionEnabled = false
            web.navigationDelegate = host
            self.web = web
            WriteRenderer.hostView?.addSubview(web)
            host.onFinish = { [weak self] in self?.measure() }
            host.onFail = { [weak self] in self?.finish(.failure(BridgeFailure("Write failed to load: \($0.localizedDescription)", code: "render_failed"))) }
            web.loadHTMLString(page, baseURL: WriteRenderer.baseURL)
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                self?.finish(.failure(BridgeFailure("Write did not finish rendering in 20 s", code: "render_timeout")))
            }
        }

        func measure() {
            let script = """
            try { await document.fonts.ready; } catch (e) {}
            await new Promise(r => { requestAnimationFrame(() => requestAnimationFrame(r)); setTimeout(r, 150); });
            const page = document.getElementById('page');
            return Math.ceil(page ? page.getBoundingClientRect().height : document.documentElement.scrollHeight);
            """
            web?.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
                guard let self, let web = self.web else { return }
                guard case .success(let value) = result, let measured = (value as? NSNumber)?.doubleValue, measured.isFinite else {
                    return self.finish(.failure(BridgeFailure("Could not measure the write", code: "render_failed")))
                }
                let height = CGFloat(max(20, min(3000, measured)))
                web.frame.size.height = height
                web.evaluateJavaScript("0") { _, _ in self.snapshot(size: CGSize(width: self.width, height: height)) }
            }
        }

        /// WebKit decides how many pixels a snapshot width yields, so the first result is checked and re-requested once.
        func snapshot(size: CGSize) {
            guard let web else { return }
            let target = WriteRenderer.rasterSize(for: size)
            let deviceScale = max(1, web.window?.screen.scale ?? web.traitCollection.displayScale)
            func attempt(width: CGFloat, retry: Bool) {
                let config = WKSnapshotConfiguration()
                config.rect = CGRect(origin: .zero, size: size)
                config.snapshotWidth = NSNumber(value: Double(width))
                config.afterScreenUpdates = true
                web.takeSnapshot(with: config) { [weak self] image, _ in
                    guard let self else { return }
                    guard let image, let cg = image.cgImage, let png = image.pngData() else {
                        return self.finish(.failure(BridgeFailure("Could not snapshot the write", code: "render_failed")))
                    }
                    let actual = CGFloat(cg.width)
                    if retry, abs(actual - target.width) > 1 { return attempt(width: width * target.width / actual, retry: false) }
                    guard CGFloat(cg.width * cg.height) <= WriteRenderer.pixelLimit else {
                        return self.finish(.failure(BridgeFailure("Write exceeds the image size limit", code: "render_failed")))
                    }
                    self.finish(.success((png, size.height)))
                }
            }
            attempt(width: target.width / deviceScale, retry: true)
        }

        func finish(_ result: Result<(png: Data, height: CGFloat), Error>) {
            guard let done else { return }
            self.done = nil
            web?.removeFromSuperview()
            web = nil
            WriteRenderer.jobs[ObjectIdentifier(self)] = nil
            done(result)
        }
    }
}
