import AppKit
import WebKit
import SquibCore

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

    // Translate eye/body/shadow elements to follow the cursor.
    // dx/dy are in SVG units, snapped to 0.5-unit grid by PetWindow.
    // - #eyes-js  moves at full offset (setAttribute, SVG units)
    // - #body-js  moves at 33% (subtle whole-body lean)
    // - #shadow-js stretches/shifts with the body lean
    func updateEyes(dx: Double, dy: Double) {
        let bdx = (dx * 0.33 * 2).rounded() / 2
        let bdy = (dy * 0.33 * 2).rounded() / 2
        let js = """
        (function(){
          var e=document.getElementById('eyes-js');
          if(e) e.setAttribute('transform','translate(\(dx),\(dy))');
          var b=document.getElementById('body-js');
          if(b) b.setAttribute('transform','translate(\(bdx),\(bdy))');
          var s=document.getElementById('shadow-js');
          if(s){
            var absDx=Math.abs(\(bdx));
            var scaleX=1+absDx*0.15;
            var shiftX=Math.round(\(bdx)*0.3*2)/2;
            s.setAttribute('transform','translate('+shiftX+',0) scale('+scaleX+',1)');
          }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Hit Test

    /// Circle hit test — synchronous, no JS.
    /// Circle centered at the window midpoint, radius 65pt.
    func isOpaque(at windowLocal: NSPoint, frameHeight: CGFloat, callback: @escaping (Bool) -> Void) {
        let cx = frameHeight / 2
        let cy = frameHeight / 2
        callback(hypot(windowLocal.x - cx, windowLocal.y - cy) < 65)
    }

    // MARK: - Loaders (internal so PetWindow can drive sequences)

    func loadSVG(name: String, flipped: Bool = false) {
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
          svg{width:100%;height:100%;\(flipped ? "transform:scaleX(-1);" : "")}
        </style></head><body>\(content)</body></html>
        """
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }

    func loadGIF(name: String, flipped: Bool = false) {
        guard let url = Bundle.module.url(forResource: name, withExtension: "gif") else {
            print("[PetView] GIF not found: \(name).gif")
            return
        }
        let flipStyle = flipped ? "transform:scaleX(-1);" : ""
        let html = """
        <!DOCTYPE html><html><head><style>
          html,body{margin:0;padding:0;width:100%;height:100%;
            background:transparent;overflow:hidden;
            display:flex;align-items:center;justify-content:center;}
          img{width:100%;height:100%;object-fit:contain;\(flipStyle)}
        </style></head><body><img src="\(url.lastPathComponent)"/></body></html>
        """
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }
}
