import AppKit
import WebKit
import SquibCore

final class BubbleWindow: NSPanel {
    static let width:           CGFloat = 340
    static let estimatedHeight: CGFloat = 170  // pre-measure fallback

    let request: PermissionRequest
    var onDecision:      ((PermissionDecision) -> Void)?
    var onTrustSession:  (() -> Void)?
    /// Fired on main thread when JS reports the card's real rendered height.
    var onHeightChanged: (() -> Void)?

    private(set) var measuredHeight: CGFloat = BubbleWindow.estimatedHeight
    private var webView: WKWebView!
    private var htmlReady = false

    init(request: PermissionRequest) {
        self.request = request
        super.init(
            contentRect: NSRect(origin: .zero,
                                size: NSSize(width: Self.width, height: Self.estimatedHeight)),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        level                = .floating
        backgroundColor      = .clear
        isOpaque             = false
        hasShadow            = true
        ignoresMouseEvents   = false
        isReleasedWhenClosed = false
        collectionBehavior   = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        setupWebView()
    }

    private func setupWebView() {
        let config  = WKWebViewConfiguration()
        let handler = BubbleMsgHandler(window: self)
        config.userContentController.add(handler, name: "squib")

        webView = WKWebView(
            frame: NSRect(origin: .zero, size: NSSize(width: Self.width, height: Self.estimatedHeight)),
            configuration: config
        )
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = handler
        webView.loadHTMLString(Self.bubbleHTML, baseURL: nil)
        contentView = webView
    }

    // MARK: - Keyboard shortcuts

    private var isDecided = false

    /// Called by BubbleManager's global key monitor. Delegates to the JS button handlers
    /// so all existing disable/elicitation/plan-review logic still applies.
    func allowViaKey() {
        guard !isDecided else { return }
        isDecided = true
        webView.evaluateJavaScript("keyAllow()", completionHandler: nil)
    }

    func denyViaKey() {
        guard !isDecided else { return }
        isDecided = true
        webView.evaluateJavaScript("keyDeny()", completionHandler: nil)
    }

    func allowSessionViaKey() {
        guard !isDecided else { return }
        isDecided = true
        webView.evaluateJavaScript("keyAllowSession()", completionHandler: nil)
    }

    // MARK: - Called by message handler

    fileprivate func didFinishLoad() {
        htmlReady = true
        injectData()
    }

    fileprivate func didReceiveHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        measuredHeight = height
        onHeightChanged?()
    }

    fileprivate func didDecide(_ decision: PermissionDecision) {
        onDecision?(decision)
    }

    // MARK: - Data injection

    private func injectData() {
        guard htmlReady else { return }

        var data: [String: Any] = [
            "toolName":      request.toolName,
            "isElicitation": request.isElicitation,
        ]

        if let raw = request.toolInput,
           let bytes = raw.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: bytes) {
            data["toolInput"] = parsed
        }

        if let sid = request.sessionId, !sid.isEmpty {
            data["sessionShortId"] = String(sid.suffix(3))
        }

        if let cwd = request.cwd, !cwd.isEmpty {
            data["sessionFolder"] = URL(fileURLWithPath: cwd).lastPathComponent
        }

        if !request.suggestions.isEmpty {
            data["suggestions"] = request.suggestions
        }

        guard let json = try? JSONSerialization.data(withJSONObject: data),
              let str  = String(data: json, encoding: .utf8) else { return }

        webView.evaluateJavaScript("loadPermission(\(str))", completionHandler: nil)
    }

    // MARK: - Positioning

    func show(at origin: NSPoint) {
        let f = NSRect(origin: origin, size: NSSize(width: Self.width, height: measuredHeight))
        if isVisible {
            setFrame(f, display: true, animate: false)
        } else {
            setFrame(f, display: false)
            orderFrontRegardless()
        }
    }

    // MARK: - Cleanup

    override func close() {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "squib")
        webView?.navigationDelegate = nil
        super.close()
    }
}

// MARK: - WKScriptMessageHandler + WKNavigationDelegate

private final class BubbleMsgHandler: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var window: BubbleWindow?
    init(window: BubbleWindow) { self.window = window }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        DispatchQueue.main.async { [weak self] in
            guard let win = self?.window else { return }
            switch body["type"] as? String {
            case "height":
                if let h = body["value"] as? Double { win.didReceiveHeight(CGFloat(h)) }
            case "decide":
                if let value = body["value"] as? String {
                    Self.handleStringDecide(value, win: win)
                } else if let value = body["value"] as? [String: Any] {
                    Self.handleObjectDecide(value, win: win)
                }
            default: break
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async { [weak self] in self?.window?.didFinishLoad() }
    }

    // MARK: - Decision resolution

    private static func handleStringDecide(_ value: String, win: BubbleWindow) {
        switch value {
        case "allow":
            win.didDecide(.allow)
        case "deny", "deny-and-focus":
            win.didDecide(.deny)
        case "trust-session":
            win.onTrustSession?()
        default:
            guard value.hasPrefix("suggestion:"),
                  let idx = Int(value.dropFirst("suggestion:".count)),
                  idx < win.request.suggestions.count else {
                win.didDecide(.allow)
                return
            }
            let raw = win.request.suggestions[idx]
            if let resolved = resolveSuggestion(raw) {
                win.didDecide(.allowWithPermissions(updatedPermissions: [resolved]))
            } else {
                win.didDecide(.allow)
            }
        }
    }

    private static func handleObjectDecide(_ value: [String: Any], win: BubbleWindow) {
        guard (value["type"] as? String) == "elicitation-submit",
              let answers = value["answers"] as? [String: Any] else {
            win.didDecide(.deny)
            return
        }
        var base: [String: Any] = [:]
        if let raw   = win.request.toolInput,
           let bytes = raw.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
            base = parsed
        }
        base["answers"] = answers
        win.didDecide(.allowWithUpdatedInput(updatedInput: base))
    }

    /// Normalises a raw suggestion object into the format Claude Code expects in `updatedPermissions`.
    private static func resolveSuggestion(_ s: [String: Any]) -> [String: Any]? {
        guard let type = s["type"] as? String else { return nil }
        switch type {
        case "addRules":
            let rules: [[String: Any]]
            if let r = s["rules"] as? [[String: Any]], !r.isEmpty {
                rules = r
            } else {
                var rule: [String: Any] = [:]
                if let tn = s["toolName"]    as? String { rule["toolName"]    = tn }
                if let rc = s["ruleContent"] as? String { rule["ruleContent"] = rc }
                rules = [rule]
            }
            return [
                "type":        "addRules",
                "destination": s["destination"] as? String ?? "localSettings",
                "behavior":    s["behavior"]    as? String ?? "allow",
                "rules":       rules,
            ]
        case "setMode":
            guard let mode = s["mode"] as? String else { return nil }
            return [
                "type":        "setMode",
                "mode":        mode,
                "destination": s["destination"] as? String ?? "localSettings",
            ]
        default:
            return nil
        }
    }
}

// MARK: - Embedded bubble HTML

private extension BubbleWindow {
    static let bubbleHTML = #"""
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }

:root {
  --card-bg:          #ffffff;
  --card-border:      rgba(0,0,0,0.08);
  --shadow:           0 4px 20px rgba(0,0,0,0.16), 0 1px 4px rgba(0,0,0,0.08);
  --text:             #18181b;
  --header:           #374151;
  --cmd-bg:           #f4f4f5;
  --cmd-border:       rgba(0,0,0,0.06);
  --cmd-color:        #374151;
  --cmd-shadow:       inset 0 1px 2px rgba(0,0,0,0.05);
  --scroll:           rgba(0,0,0,0.14);
  --deny-bg:          #ffffff;
  --deny-color:       #52525b;
  --deny-border:      #d1d5db;
  --sug-bg:           #ffffff;
  --sug-color:        #71717a;
  --sug-border:       #e5e7eb;
  --sug-hover-bg:     #f9fafb;
  --sug-hover-border: #d1d5db;
  --sug-hover-color:  #374151;
  --opt-bg:           rgba(0,0,0,0.02);
}
@media (prefers-color-scheme: dark) {
  :root {
    --card-bg:          #18181b;
    --card-border:      rgba(255,255,255,0.10);
    --shadow:           0 4px 20px rgba(0,0,0,0.35);
    --text:             #f4f4f5;
    --header:           #e4e4e7;
    --cmd-bg:           #09090b;
    --cmd-border:       rgba(255,255,255,0.06);
    --cmd-color:        #a1a1aa;
    --cmd-shadow:       inset 0 2px 4px rgba(0,0,0,0.20);
    --scroll:           rgba(255,255,255,0.12);
    --deny-bg:          rgba(255,255,255,0.05);
    --deny-color:       #e4e4e7;
    --deny-border:      rgba(255,255,255,0.10);
    --sug-bg:           rgba(255,255,255,0.03);
    --sug-color:        #a1a1aa;
    --sug-border:       rgba(255,255,255,0.06);
    --sug-hover-bg:     rgba(255,255,255,0.08);
    --sug-hover-border: rgba(255,255,255,0.15);
    --sug-hover-color:  #e4e4e7;
    --opt-bg:           rgba(255,255,255,0.03);
  }
}

html, body {
  width: 100%;
  background: transparent;
  overflow: hidden;
  user-select: none;
  font-family: -apple-system, BlinkMacSystemFont, sans-serif;
  -webkit-font-smoothing: antialiased;
}
body { padding: 6px; }

/* ── Card ── */
.card {
  background: var(--card-bg);
  border: 1px solid var(--card-border);
  border-radius: 14px;
  padding: 14px 16px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  color: var(--text);
  box-shadow: var(--shadow);
  opacity: 0;
  transform: translateX(40px);
  transition: opacity 0.28s ease, transform 0.32s ease;
}
.card.visible { opacity: 1; transform: translateX(0); }

/* ── Header ── */
.header { display: flex; align-items: center; justify-content: space-between; }
.header-title {
  font-size: 12px;
  font-weight: 600;
  color: var(--header);
  letter-spacing: 0.02em;
}

/* ── Tool pill ── */
.pill {
  display: inline-flex;
  align-items: center;
  padding: 2px 8px;
  border-radius: 5px;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: #fff;
  background: #52525b;
}
.pill[data-tool="Bash"]  { background: #d97757; }
.pill[data-tool="Edit"]  { background: #5b8dd9; }
.pill[data-tool="Write"] { background: #8b7ec7; }
.pill[data-tool="Read"]  { background: #5a9e6f; }
.pill[data-tool="Glob"],
.pill[data-tool="Grep"]  { background: #5a9eab; }
.pill[data-tool="Agent"] { background: #c47a9a; }

/* ── Session tag ── */
.stag {
  display: none;
  font-size: 10px;
  color: var(--cmd-color);
  font-family: "SF Mono", ui-monospace, monospace;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  margin-top: -4px;
  opacity: 0.8;
}
.stag.visible { display: block; }

/* ── Command block ── */
.cmd {
  padding: 10px 12px;
  background: var(--cmd-bg);
  border: 1px solid var(--cmd-border);
  border-radius: 8px;
  font-family: "SF Mono", ui-monospace, "Cascadia Code", monospace;
  font-size: 11px;
  line-height: 1.55;
  color: var(--cmd-color);
  max-height: 120px;
  overflow-y: auto;
  word-break: break-all;
  white-space: pre-wrap;
  box-shadow: var(--cmd-shadow);
}
.cmd:empty { display: none; }
.cmd::-webkit-scrollbar       { width: 5px; }
.cmd::-webkit-scrollbar-track { background: transparent; }
.cmd::-webkit-scrollbar-thumb { background: var(--scroll); border-radius: 3px; }

/* ── Elicitation form ── */
.eform { display: none; flex-direction: column; gap: 10px; }
.eform.visible { display: flex; }

.question-card {
  padding: 12px;
  background: var(--cmd-bg);
  border: 1px solid var(--cmd-border);
  border-radius: 8px;
  box-shadow: var(--cmd-shadow);
}
.q-header {
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--cmd-color);
  opacity: 0.85;
}
.q-text {
  margin-top: 5px;
  font-size: 13px;
  line-height: 1.45;
  color: var(--text);
}
.q-hint {
  margin-top: 3px;
  font-size: 10px;
  color: var(--cmd-color);
  opacity: 0.85;
}
.option-list { display: flex; flex-direction: column; gap: 5px; margin-top: 8px; }
.option-item {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 7px 10px;
  border-radius: 7px;
  border: 1px solid var(--cmd-border);
  background: var(--opt-bg);
  cursor: pointer;
}
.option-item input { margin-top: 2px; accent-color: #d97757; }
.option-copy  { display: flex; flex: 1; flex-direction: column; gap: 2px; }
.option-label { font-size: 12px; line-height: 1.4; color: var(--text); }
.option-desc  { font-size: 11px; line-height: 1.35; color: var(--cmd-color); }

/* ── Action buttons ── */
.actions { display: flex; gap: 8px; }
.btn {
  flex: 1;
  padding: 6px 0;
  border-radius: 7px;
  font-family: inherit;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  border: 1px solid transparent;
  outline: none;
  transition: filter 0.12s;
}
.btn:disabled                 { opacity: 0.45; cursor: not-allowed; }
.btn:not(:disabled):hover     { filter: brightness(0.90); }
.btn:not(:disabled):active    { filter: brightness(0.78); }
.allow { background: #d97757; color: #fff; }
.deny  { background: var(--deny-bg); color: var(--deny-color); border-color: var(--deny-border); }

/* ── Suggestion buttons ── */
.sugs { display: flex; flex-direction: column; gap: 5px; }
.btn-sug {
  display: block;
  width: 100%;
  padding: 6px 12px;
  background: var(--sug-bg);
  color: var(--sug-color);
  border: 1px solid var(--sug-border);
  border-radius: 7px;
  font-family: inherit;
  font-size: 11.5px;
  font-weight: 500;
  cursor: pointer;
  transition: background 0.15s, border-color 0.15s, color 0.15s, padding-right 0.15s;
  outline: none;
  text-align: left;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  position: relative;
}
.btn-sug::after {
  content: '→';
  position: absolute;
  right: 12px;
  opacity: 0;
  transform: translateX(-4px);
  transition: opacity 0.15s, transform 0.15s;
  color: var(--sug-hover-color);
}
.btn-sug:hover {
  background: var(--sug-hover-bg);
  border-color: var(--sug-hover-border);
  color: var(--sug-hover-color);
  padding-right: 28px;
}
.btn-sug:hover::after { opacity: 1; transform: translateX(0); }
.btn-sug:active { filter: brightness(0.88); }
.btn-sug:disabled { opacity: 0.4; cursor: not-allowed; }

/* ── Keyboard hint badges ── */
.kbd-hint {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 14px;
  height: 14px;
  border-radius: 3px;
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0;
  opacity: 0.45;
  border: 1px solid currentColor;
  vertical-align: middle;
  margin-left: 5px;
  line-height: 1;
  flex-shrink: 0;
}
</style>
</head>
<body>
<div class="card" id="card">
  <div class="header">
    <span class="header-title" id="title">Permission Request</span>
    <span class="pill" id="pill"></span>
  </div>
  <div class="stag"  id="stag"></div>
  <div class="cmd"   id="cmd"></div>
  <div class="eform" id="eform"></div>
  <div class="actions">
    <button class="btn deny"  id="btnDeny">Deny <span class="kbd-hint">N</span></button>
    <button class="btn allow" id="btnAllow">Allow <span class="kbd-hint">Y</span></button>
  </div>
  <div class="sugs" id="sugs">
    <button class="btn-sug" id="btnAllowSession" style="display:none">Allow Session <span class="kbd-hint">A</span></button>
  </div>
</div>
<script>
const card     = document.getElementById("card");
const title    = document.getElementById("title");
const pill     = document.getElementById("pill");
const stag     = document.getElementById("stag");
const cmd      = document.getElementById("cmd");
const eform    = document.getElementById("eform");
const btnAllow = document.getElementById("btnAllow");
const btnDeny  = document.getElementById("btnDeny");
const sugs            = document.getElementById("sugs");
const btnAllowSession = document.getElementById("btnAllowSession");

let elicitationMode = false;
let elicitationQs   = [];

function post(msg) { window.webkit.messageHandlers.squib.postMessage(msg); }

// ── Tool input extraction ────────────────────────────────────────────────

function detail(name, inp) {
  if (!inp || typeof inp !== "object") return "";
  if (name === "Bash"  && inp.command)   return inp.command;
  if ((name === "Edit" || name === "Write" || name === "Read") && inp.file_path)
    return inp.file_path;
  if ((name === "Glob" || name === "Grep") && inp.pattern)
    return inp.pattern;
  for (const v of Object.values(inp)) { if (typeof v === "string" && v) return v; }
  try { return JSON.stringify(inp, null, 2); } catch { return ""; }
}

// ── Session tag ──────────────────────────────────────────────────────────

function setSessionTag(data) {
  const parts = [];
  if (data.sessionFolder) parts.push(data.sessionFolder);
  if (data.sessionShortId) parts.push("#" + data.sessionShortId);
  if (parts.length) {
    stag.textContent = parts.join(" · ");
    stag.classList.add("visible");
  }
}

// ── Suggestion buttons ───────────────────────────────────────────────────

function getSuggestionLabel(s) {
  if (s.type === "setMode") {
    if (s.mode === "acceptEdits") return "Auto-accept edits";
    if (s.mode === "plan")        return "Switch to plan mode";
    return s.mode;
  }
  if (s.type === "addRules") {
    const rule = Array.isArray(s.rules) && s.rules[0] ? s.rules[0] : s;
    const rc = rule.ruleContent || s.ruleContent;
    const tn = rule.toolName || s.toolName || "";
    if (rc) {
      if (rc.includes("**")) {
        const dir = rc.split("**")[0].replace(/[\/\\]$/, "").split(/[\/\\]/).pop() || rc;
        return "Allow " + tn + " in " + dir + "/";
      }
      const short = rc.length > 30 ? rc.slice(0, 29) + "\u2026" : rc;
      return "Always allow `" + short + "`";
    }
  }
  return "Always allow";
}

function renderSuggestions(list) {
  sugs.innerHTML = "";
  if (!list || !list.length) return;
  const seen = new Set();
  list.forEach((s, i) => {
    const label = getSuggestionLabel(s);
    if (seen.has(label)) return;
    seen.add(label);
    const btn = document.createElement("button");
    btn.className = "btn-sug";
    btn.textContent = label;
    btn.addEventListener("click", () => {
      disableAll();
      post({ type: "decide", value: "suggestion:" + i });
    });
    sugs.appendChild(btn);
  });
}

// ── Elicitation form ─────────────────────────────────────────────────────

function isAnswered(qCard) {
  return [...qCard.querySelectorAll("input")].some(i => i.checked);
}

function updateSubmitState() {
  if (!elicitationMode) return;
  const cards = [...eform.querySelectorAll(".question-card")];
  btnAllow.disabled = !(
    elicitationQs.length > 0 &&
    cards.length === elicitationQs.length &&
    cards.every(isAnswered)
  );
}

function collectAnswers() {
  const answers = {};
  const cards = [...eform.querySelectorAll(".question-card")];
  for (let i = 0; i < elicitationQs.length; i++) {
    const q = elicitationQs[i];
    const qcard = cards[i];
    if (!q || !qcard) return null;
    const vals = [...qcard.querySelectorAll("input:checked")]
      .map(inp => inp.getAttribute("data-answer") || inp.value)
      .filter(Boolean);
    if (!vals.length) return null;
    answers[q.question] = vals.join(", ");
  }
  return answers;
}

function renderElicitationForm(data) {
  elicitationQs = (data.toolInput && Array.isArray(data.toolInput.questions))
    ? data.toolInput.questions : [];
  eform.innerHTML = "";
  elicitationQs.forEach((q, qi) => {
    const qcard = document.createElement("div");
    qcard.className = "question-card";

    const hdr = document.createElement("div");
    hdr.className = "q-header";
    hdr.textContent = q.header || ("Question " + (qi + 1));
    qcard.appendChild(hdr);

    const txt = document.createElement("div");
    txt.className = "q-text";
    txt.textContent = q.question || "";
    qcard.appendChild(txt);

    const hint = document.createElement("div");
    hint.className = "q-hint";
    hint.textContent = q.multiSelect
      ? "Multi-select, choose at least one"
      : "Choose one option";
    qcard.appendChild(hint);

    const optList = document.createElement("div");
    optList.className = "option-list";
    const options = Array.isArray(q.options) ? q.options : [];
    options.forEach((opt, oi) => {
      const lbl = document.createElement("label");
      lbl.className = "option-item";

      const inp = document.createElement("input");
      inp.type = q.multiSelect ? "checkbox" : "radio";
      inp.name = "eq-" + qi;
      inp.value = opt.label || "";
      inp.setAttribute("data-answer", opt.label || "");
      inp.addEventListener("change", updateSubmitState);

      const copy = document.createElement("span");
      copy.className = "option-copy";

      const olbl = document.createElement("span");
      olbl.className = "option-label";
      olbl.textContent = opt.label || String(oi + 1);
      copy.appendChild(olbl);

      if (opt.description) {
        const odesc = document.createElement("span");
        odesc.className = "option-desc";
        odesc.textContent = opt.description;
        copy.appendChild(odesc);
      }

      lbl.appendChild(inp);
      lbl.appendChild(copy);
      optList.appendChild(lbl);
    });
    qcard.appendChild(optList);
    eform.appendChild(qcard);
  });
  updateSubmitState();
}

// ── Disable all interactive elements ────────────────────────────────────

function disableAll() {
  btnAllow.disabled        = true;
  btnDeny.disabled         = true;
  btnAllowSession.disabled = true;
  for (const b of sugs.children)             b.disabled = true;
  for (const i of eform.querySelectorAll("input")) i.disabled = true;
}

// ── Reveal + height report ───────────────────────────────────────────────

function revealCard() {
  requestAnimationFrame(() => {
    card.classList.add("visible");
    requestAnimationFrame(() => {
      // 12px = 6px top body padding + 6px bottom
      post({ type: "height", value: card.offsetHeight + 12 });
    });
  });
}

// ── Main entry point ─────────────────────────────────────────────────────

function loadPermission(data) {
  const name = data.toolName || "Unknown";
  setSessionTag(data);

  // ── Elicitation mode ──
  if (data.isElicitation) {
    elicitationMode = true;
    title.textContent = "Needs Input";
    pill.style.display = "none";
    cmd.style.display  = "none";
    eform.classList.add("visible");
    renderElicitationForm(data);
    btnAllow.textContent = "Submit Answer";
    btnAllow.disabled    = true;
    btnDeny.textContent  = "Go to Terminal";
    revealCard();
    return;
  }

  // ── Plan review mode ──
  if (name === "ExitPlanMode") {
    title.textContent    = "Plan Review";
    pill.style.display   = "none";
    btnDeny.style.display = "none";
    cmd.textContent      = detail(name, data.toolInput);
    btnAllow.textContent = "Approve";
    // "Go to Terminal" as suggestion-style button below actions
    const btn = document.createElement("button");
    btn.className   = "btn-sug";
    btn.textContent = "Go to Terminal";
    btn.addEventListener("click", () => {
      disableAll();
      post({ type: "decide", value: "deny-and-focus" });
    });
    sugs.appendChild(btn);
    revealCard();
    return;
  }

  // ── Regular permission request ──
  pill.textContent = name;
  pill.setAttribute("data-tool", name);
  cmd.textContent  = detail(name, data.toolInput);
  renderSuggestions(data.suggestions);
  if (data.suggestions && data.suggestions.length > 0) {
    sugs.prepend(btnAllowSession);
    btnAllowSession.style.display = "";
  }
  revealCard();
}

// ── Button handlers ──────────────────────────────────────────────────────

btnAllow.addEventListener("click", () => {
  if (elicitationMode) {
    const answers = collectAnswers();
    if (!answers) return;
    disableAll();
    post({ type: "decide", value: { type: "elicitation-submit", answers } });
    return;
  }
  disableAll();
  post({ type: "decide", value: "allow" });
});

btnDeny.addEventListener("click", () => {
  disableAll();
  post({ type: "decide", value: "deny" });
});

btnAllowSession.addEventListener("click", () => {
  disableAll();
  post({ type: "decide", value: "trust-session" });
});

// ── Keyboard shortcut entry points (called from Swift) ───────────────────

function keyAllow() {
  if (!btnAllow.disabled) btnAllow.click();
}
function keyDeny() {
  if (!btnDeny.disabled) btnDeny.click();
}
function keyAllowSession() {
  const btn = document.getElementById("btnAllowSession");
  if (btn && !btn.disabled) { btn.click(); return; }
  keyAllow();  // fallback when no session id or wrong mode
}
</script>
</body>
</html>
"""#
}
