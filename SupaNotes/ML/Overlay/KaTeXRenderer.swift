import UIKit
import WebKit

/// Renders LaTeX strings to UIImage using a hidden WKWebView with bundled KaTeX.
final class KaTeXRenderer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var isReady = false
    private var readyContinuation: CheckedContinuation<Void, Never>?

    /// Initialize and load the KaTeX HTML page.
    func warmUp() async {
        guard webView == nil else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.readyContinuation = cont
            let config = WKWebViewConfiguration()
            let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 256), configuration: config)
            wv.isOpaque = false
            wv.backgroundColor = .clear
            wv.scrollView.backgroundColor = .clear
            wv.navigationDelegate = self
            self.webView = wv

            guard let htmlURL = Bundle.main.url(forResource: "render", withExtension: "html", subdirectory: "katex") else {
                print("[KaTeXRenderer] render.html not found in bundle")
                cont.resume()
                return
            }
            wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        readyContinuation?.resume()
        readyContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[KaTeXRenderer] load failed: \(error)")
        readyContinuation?.resume()
        readyContinuation = nil
    }

    /// Render a LaTeX string to a UIImage.
    /// - Parameters:
    ///   - latex: Full LaTeX expression (e.g. `\sum_{n=0}^{\infty} a_n`)
    ///   - fontSize: Target font size in points
    /// - Returns: Rendered UIImage with transparent background
    func render(latex: String, fontSize: CGFloat = 20) async throws -> UIImage {
        if !isReady { await warmUp() }
        guard let wv = webView, isReady else {
            throw RenderError.notReady
        }

        let escaped = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")

        let js = "renderLatex('\(escaped)', \(fontSize))"
        let result = try await wv.evaluateJavaScript(js)

        guard let jsonString = result as? String,
              let data = jsonString.data(using: .utf8),
              let size = try? JSONDecoder().decode(RenderSize.self, from: data) else {
            throw RenderError.badResponse
        }

        let snapshotConfig = WKSnapshotConfiguration()
        snapshotConfig.rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        snapshotConfig.snapshotWidth = NSNumber(value: Double(size.width))

        let image = try await wv.takeSnapshot(configuration: snapshotConfig)
        return image
    }

    enum RenderError: Error {
        case notReady
        case badResponse
    }

    private struct RenderSize: Decodable {
        let width: CGFloat
        let height: CGFloat
    }
}
