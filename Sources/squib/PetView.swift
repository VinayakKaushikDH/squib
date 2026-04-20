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
        loadState(.idle)
    }

    func loadState(_ state: PetState) {
        switch state.assetExtension {
        case "svg": loadSVG(name: state.assetName)
        default:    loadGIF(name: state.assetName)
        }
    }

    /// Swaps SVG content in-place via JS — no page reload, no flash.
    /// Use this for sequence steps where the webview already has an SVG loaded.
    func swapInlineSVG(name: String) {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            print("[PetView] SVG not found for swap: \(name).svg")
            return
        }
        // Use JS template literal — SVGs won't contain backticks.
        let escaped = content.replacingOccurrences(of: "\\", with: "\\\\")
        let js = "document.body.innerHTML = `\(escaped)`;"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // Translate #eyes-js to follow the cursor. dx/dy are in SVG units,
    // already clamped to max 3.0 by PetWindow. No-op if element is absent.
    func updateEyes(dx: Double, dy: Double) {
        let js = """
        (function(){
          var e=document.getElementById('eyes-js');
          if(e) e.style.transform='translate(\(dx)px,\(dy)px)';
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Loaders (internal so PetWindow can drive sequences)

    func loadSVG(name: String) {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            print("[PetView] SVG not found: \(name).svg")
            return
        }
        let html = """
        <!DOCTYPE html><html><head><style>
          html,body{margin:0;padding:0;width:100%;height:100%;
            background:transparent;overflow:hidden;
            display:flex;align-items:center;justify-content:center;}
          svg{width:100%;height:100%;}
        </style></head><body>\(content)</body></html>
        """
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }

    func loadGIF(name: String) {
        guard let url = Bundle.module.url(forResource: name, withExtension: "gif") else {
            print("[PetView] GIF not found: \(name).gif")
            return
        }
        let html = """
        <!DOCTYPE html><html><head><style>
          html,body{margin:0;padding:0;width:100%;height:100%;
            background:transparent;overflow:hidden;
            display:flex;align-items:center;justify-content:center;}
          img{width:100%;height:100%;object-fit:contain;}
        </style></head><body><img src="\(url.lastPathComponent)"/></body></html>
        """
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }
}
