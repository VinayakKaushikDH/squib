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
        loadSVG(name: state.assetName)
    }

    /// Swaps SVG content in-place via JS — no page reload, no flash.
    /// Use this for sequence steps where the webview already has an SVG loaded.
    func swapInlineSVG(name: String) {
        currentSVGName = name
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

    // MARK: - Hit Rect

    // SVG coordinate system: viewBox = "-15 -25 45 45" (same as reference theme.json).
    // Reference hitBoxes (SVG units) map to these pixel rects in a 200×200 AppKit window
    // (y-from-bottom). Derived from the same geometry as the reference's getHitRectScreen():
    //   artRect: x=-30.5, y_top=-53.6, w=261, h=261  (scale = 261/45 = 5.8 px/unit)
    //   appkit_y = 200 - web_y
    //
    //   default  {x:-1,y:5,w:17,h:12} → x:[50.7,149.3]  y:[10.0, 79.6]
    //   wide     {x:-3,y:3,w:21,h:14} → x:[39.1,160.9]  y:[10.0, 91.2]
    //   sleeping {x:-2,y:9,w:19,h: 7} → x:[44.9,155.1]  y:[15.8, 56.4]

    private static let hitRectDefault  = NSRect(x: 50.7, y: 10.0, width:  98.6, height: 69.6)
    private static let hitRectWide     = NSRect(x: 39.1, y: 10.0, width: 121.8, height: 81.2)
    private static let hitRectSleeping = NSRect(x: 44.9, y: 15.8, width: 110.2, height: 40.6)

    // SVGs that use the wider hitbox (arms out — conducting, error, notification).
    private static let wideSVGs: Set<String> = [
        "clawd-error",
        "clawd-notification",
        "clawd-working-conducting",
    ]

    // SVGs that use the sleeping (low, wide) hitbox.
    private static let sleepingSVGs: Set<String> = [
        "clawd-sleeping",
        "clawd-idle-collapse",
    ]

    private(set) var currentSVGName: String = "clawd-idle-follow"

    /// Hit rect for the current SVG in 200×200 window-local AppKit coordinates (y-from-bottom).
    var hitRect: NSRect {
        if PetView.sleepingSVGs.contains(currentSVGName) { return PetView.hitRectSleeping }
        if PetView.wideSVGs.contains(currentSVGName)     { return PetView.hitRectWide     }
        return PetView.hitRectDefault
    }

    // MARK: - Loaders (internal so PetWindow can drive sequences)

    func loadSVG(name: String, flipped: Bool = false) {
        currentSVGName = name
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
}
