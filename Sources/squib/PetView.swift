import AppKit
import WebKit

final class PetView: NSView {
    private let webView: WKWebView

    override init(frame: NSRect) {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        webView.setValue(false, forKey: "drawsBackground")
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        loadState("idle")
    }

    func loadState(_ name: String) {
        let svgURL = Bundle.module.url(forResource: name, withExtension: "svg")
        let svgContent: String
        if let url = svgURL, let content = try? String(contentsOf: url, encoding: .utf8) {
            svgContent = content
        } else {
            svgContent = fallbackSVG
        }

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <style>
          html, body {
            margin: 0; padding: 0;
            width: 100%; height: 100%;
            background: transparent;
            overflow: hidden;
            display: flex;
            align-items: center;
            justify-content: center;
          }
          svg { width: 100%; height: 100%; }
        </style>
        </head>
        <body>\(svgContent)</body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: svgURL?.deletingLastPathComponent())
    }

    // Move pupils toward the cursor. dx/dy are offsets from socket centers in SVG units,
    // already clamped to the socket radius. No-op if the current state has no lp/rp elements.
    func updateEyes(dx: Double, dy: Double) {
        let js = """
        (function() {
          var lp = document.getElementById('lp');
          var rp = document.getElementById('rp');
          if (!lp || !rp) return;
          lp.setAttribute('cx', \(38 + dx));
          lp.setAttribute('cy', \(44 + dy));
          rp.setAttribute('cx', \(62 + dx));
          rp.setAttribute('cy', \(44 + dy));
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private let fallbackSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 120">
      <ellipse cx="50" cy="52" rx="36" ry="40" fill="#6B73FF"/>
      <circle cx="38" cy="44" r="7" fill="white"/>
      <circle cx="62" cy="44" r="7" fill="white"/>
      <circle id="lp" cx="40" cy="45" r="3.5" fill="#1a1a2e"/>
      <circle id="rp" cx="64" cy="45" r="3.5" fill="#1a1a2e"/>
      <path d="M 40 64 Q 50 72 60 64" stroke="white" stroke-width="2.5" fill="none" stroke-linecap="round"/>
    </svg>
    """
}
