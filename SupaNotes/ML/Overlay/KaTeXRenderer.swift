import UIKit
import WebKit

struct KaTeXRenderResult {
    let image: UIImage
    let size: CGSize
    let characters: [OverlayCharacter]
}

final class KaTeXRenderer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var isReady = false
    private var readyContinuation: CheckedContinuation<Void, Never>?

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

    func render(latex: String, fontSize: CGFloat = 20) async throws -> KaTeXRenderResult {
        if !isReady { await warmUp() }
        guard let wv = webView, isReady else { throw RenderError.notReady }

        let escaped = latex
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")

        let js = "renderLatex('\(escaped)', \(fontSize), true)"
        let result = try await wv.evaluateJavaScript(js)

        guard let jsonString = result as? String,
              let data = jsonString.data(using: .utf8) else {
            throw RenderError.badResponse
        }

        print("[KaTeXRenderer] raw response: \(jsonString.prefix(500))")

        guard let response = try? JSONDecoder().decode(RenderResponse.self, from: data) else {
            throw RenderError.badResponse
        }

        let snapshotConfig = WKSnapshotConfiguration()
        snapshotConfig.rect = CGRect(x: 0, y: 0, width: response.width, height: response.height)
        snapshotConfig.snapshotWidth = NSNumber(value: Double(response.width))
        let image = try await wv.takeSnapshot(configuration: snapshotConfig)

        // Convert leaf rects directly into OverlayCharacters
        let characters = response.leafRects.enumerated().map { i, leaf in
            OverlayCharacter(
                id: "c-\(i)",
                index: i,
                displayLatex: leaf.text,
                sourceToken: .latex,
                rect: CGRect(x: leaf.x, y: leaf.y, width: leaf.width, height: leaf.height)
            )
        }

        print("[KaTeXRenderer] \(characters.count) leaf glyphs found")

        return KaTeXRenderResult(image: image, size: CGSize(width: response.width, height: response.height), characters: characters)
    }

    enum RenderError: Error {
        case notReady
        case badResponse
    }

    private struct RenderResponse: Decodable {
        let width: CGFloat
        let height: CGFloat
        let leafRects: [LeafRect]
    }

    private struct LeafRect: Decodable {
        let text: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }
}
