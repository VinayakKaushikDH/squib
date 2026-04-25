// Main page renderer — zine character sheet + Apple glass UI system.

(function () {
  const page = document.getElementById('page');

  // ---------- Masthead ----------
  page.insertAdjacentHTML('beforeend', `
    <header class="masthead">
      <div class="issue">ISS. 002 · APR 24 2026</div>
      <h1 class="title">squib<span class="dot">.</span></h1>
      <div class="date">desktop companion · handoff v2</div>
    </header>

    <div class="note">
      <b>Design update:</b> pet stays zine-inky (hand-drawn ink, transparent, lives on your wallpaper).
      UI surfaces — permission card, elicitation, chat — move to <b>Apple Liquid Glass</b>: translucent dark, rounded, vibrant, inline keybindings.
      Try the <b>Tweaks</b> panel to swap ink weight, body color, accent, paper texture for the pet sheet.
    </div>
  `);

  // ---------- Section 01 — Character sheet ----------
  page.insertAdjacentHTML('beforeend', `
    <div class="section-label"><span class="n">01</span> Character sheet</div>
    <h2 class="heading">Meet squib.</h2>
    <div class="subhead">A crab with a shell like a photocopied zine. Grumpy exterior, loyal underneath. Sits on top of your screen, watches your agent work.</div>
    <section class="char-sheet">
      <div class="hero">
        <div class="name-tag">squib</div>
        ${crab({ state: 'idle', size: 200 })}
        <div class="tagline">— small crab · big opinions —</div>
        <div class="anatomy-callouts">
          <div class="callout tl"><span class="dot"></span><span class="line"></span>stalk eyes</div>
          <div class="callout tr">carapace<span class="line"></span><span class="dot"></span></div>
          <div class="callout bl"><span class="dot"></span><span class="line"></span>pincer</div>
          <div class="callout br">walker legs<span class="line"></span><span class="dot"></span></div>
        </div>
      </div>
      <div class="specs">
        <div class="spec-row"><span class="k">species</span><span class="v">Rectangular crab · felt-tip family</span></div>
        <div class="spec-row"><span class="k">disposition</span><span class="v">Gruff, loyal, observant</span></div>
        <div class="spec-row"><span class="k">habitat</span><span class="v">Top-layer · floats over windows</span></div>
        <div class="spec-row"><span class="k">shell</span><span class="v"><span class="chip" id="chip-shell"></span><span id="chip-shell-hex">warm clay</span></span></div>
        <div class="spec-row"><span class="k">ink</span><span class="v"><span class="chip" id="chip-ink"></span>near-black warm</span></div>
        <div class="spec-row"><span class="k">accent</span><span class="v"><span class="chip" id="chip-accent"></span><span id="chip-accent-hex">rust</span></span></div>
        <div class="spec-row"><span class="k">linework</span><span class="v" id="chip-weight">2.2px felt-tip</span></div>
        <div class="spec-row"><span class="k">canvas</span><span class="v">200 × 220 @2x · alpha</span></div>
        <div class="spec-row"><span class="k">ui shell</span><span class="v">Apple Liquid Glass · dark-first</span></div>
      </div>
    </section>

    <div class="section-label"><span class="n">02</span> Palette &amp; weight</div>
    <div class="swatch-row">
      <div class="swatch"><div class="chip" style="background: var(--paper);"></div>Paper<span class="hex" id="hex-paper">#f2ebdc</span></div>
      <div class="swatch"><div class="chip" style="background: var(--paper-2);"></div>Paper·2<span class="hex" id="hex-paper2">#ede4cf</span></div>
      <div class="swatch"><div class="chip" style="background: var(--ink);"></div>Ink<span class="hex">#1f1a10</span></div>
      <div class="swatch"><div class="chip" style="background: var(--accent-soft);"></div>Shell<span class="hex" id="hex-shell">warm clay</span></div>
      <div class="swatch"><div class="chip" style="background: var(--accent);"></div>Accent<span class="hex" id="hex-accent">#c24d2c</span></div>
    </div>

    <div class="section-label"><span class="n">03</span> Ink weight</div>
    <div class="ink-weights" id="ink-weights"></div>
  `);

  const iw = document.getElementById('ink-weights');
  const weights = [
    { name: 'Pen', lbl: '1.4 px', w: 1.4 },
    { name: 'Felt', lbl: '2.2 px · default', w: 2.2 },
    { name: 'Marker', lbl: '3.4 px', w: 3.4 },
  ];
  iw.innerHTML = weights.map(x => `
    <div class="iw" style="--ink-w: ${x.w};">
      <div class="name">${x.name}</div>
      <div class="sample">${crab({ state: 'idle', size: 110 })}</div>
      <div class="lbl">${x.lbl}</div>
    </div>`).join('');

  // ---------- Section 04 — Core states ----------
  page.insertAdjacentHTML('beforeend', `
    <div class="section-label"><span class="n">04</span> Core states · v1 ship</div>
    <h2 class="heading">Six states, one soul.</h2>
    <div class="subhead">The six animation loops for v1. CSS-driven preview → APNG export. Body geometry stays constant; expression + props carry the state.</div>
  `);

  const states = [
    { s: 'idle',      label: 'Idle',      tag: 'between tasks',       stamp: 'DEFAULT' },
    { s: 'thinking',  label: 'Thinking',  tag: 'formulating',          stamp: '' },
    { s: 'working',   label: 'Working',   tag: 'tool in progress',     stamp: 'LOOP' },
    { s: 'sleeping',  label: 'Sleeping',  tag: 'session ended',        stamp: 'SLOWS' },
    { s: 'error',     label: 'Error',     tag: 'distressed',           stamp: 'URGENT' },
    { s: 'attention', label: 'Attention', tag: 'permission requested', stamp: 'WAVES' },
  ];

  const grid = document.createElement('section');
  grid.className = 'grid-states';
  grid.innerHTML = states.map(st => `
    <div class="cell">
      ${st.stamp ? `<div class="stamp">${st.stamp}</div>` : ''}
      <div class="stage">${crab({ state: st.s, size: 170 })}</div>
      <div class="label"><span>${st.label}</span><span class="tag">${st.tag}</span></div>
    </div>`).join('');
  page.appendChild(grid);

  // Idle-reading bonus
  page.insertAdjacentHTML('beforeend', `
    <div class="section-label"><span class="n">04·b</span> Bonus &amp; rules</div>
    <section class="grid-states" style="grid-template-columns: 1fr 1fr 1fr;">
      <div class="cell">
        <div class="stamp">BONUS</div>
        <div class="stage">${crab({ state: 'idle-reading', size: 170 })}</div>
        <div class="label"><span>Idle · reading</span><span class="tag">perusing a zine</span></div>
      </div>
      <div class="cell">
        <div class="stage" style="flex-direction:column; gap:10px;">
          <div style="font-family: var(--mono); font-size: 11px; letter-spacing: 0.18em; text-transform: uppercase; color: var(--ink-mute);">Expression rule</div>
          <p style="font-family: var(--mono); font-size: 12px; line-height: 1.6; color: var(--ink); margin: 0; max-width: 260px; text-align: center;">
            Grumpy = flat mouth, short eye slits, claws forward. Happy lifts mouth corners. Never smiles fully.
          </p>
        </div>
        <div class="label"><span>Expression rule</span><span class="tag">never smiles fully</span></div>
      </div>
      <div class="cell">
        <div class="stage" style="flex-direction:column; gap:8px;">
          <div style="display:flex; gap: 4px; align-items:end;">
            <div style="width: 30px; height: 14px; border: 1.5px solid var(--ink); background: var(--paper);"></div>
            <div style="width: 30px; height: 22px; border: 1.5px solid var(--ink); background: var(--accent-soft);"></div>
            <div style="width: 30px; height: 30px; border: 1.5px solid var(--ink); background: var(--ink);"></div>
            <div style="width: 30px; height: 18px; border: 1.5px solid var(--ink); background: var(--accent);"></div>
          </div>
          <div style="font-family: var(--mono); font-size: 10px; letter-spacing: 0.15em; text-transform: uppercase; color: var(--ink-mute); margin-top: 8px;">Value · paper → ink → accent</div>
        </div>
        <div class="label"><span>Value pass</span><span class="tag">4-step ramp</span></div>
      </div>
    </section>
  `);

  // ---------- Section 05 — Mini mode ----------
  page.insertAdjacentHTML('beforeend', `
    <div class="section-label"><span class="n">05</span> Mini mode · edge peek</div>
    <h2 class="heading">Peeks from the edge.</h2>
    <div class="subhead">When collapsed, squib leans in from a screen edge. Three poses. Designs render right-edge; horizontally mirror for left/bottom.</div>
  `);

  const minis = [
    { s: 'mini-idle',  label: 'Mini · idle',  tag: 'neutral peek' },
    { s: 'mini-peek',  label: 'Mini · peek',  tag: 'curious lean-in' },
    { s: 'mini-alert', label: 'Mini · alert', tag: 'wide-eyes, needs you' },
  ];
  const mg = document.createElement('section');
  mg.className = 'grid-states grid-mini';
  mg.innerHTML = minis.map(m => `
    <div class="cell">
      <div class="stage">${crab({ mini: m.s, size: 140 })}</div>
      <div class="label"><span>${m.label}</span><span class="tag">${m.tag}</span></div>
    </div>`).join('');
  page.appendChild(mg);

  // ---------- Section 06 — Permission bubble (Apple glass) ----------
  page.insertAdjacentHTML('beforeend', `
    <div class="section-label"><span class="n">06</span> Permission bubble · liquid glass</div>
    <h2 class="heading">The interaction surface.</h2>
    <div class="subhead">
      Apple Liquid Glass, dark-first. Every action carries its keybinding inline — <span style="font-family:var(--mono); color: var(--ink);">[⌘⇧Y]</span>, <span style="font-family:var(--mono); color: var(--ink);">[⌘⇧N]</span>.
      Compact variant drops the command body to stay tight. Elicitation groups the question in a nested glass panel.
    </div>
    <section class="glass-grid">
      <div class="desktop-stage">
        <div class="stage-label">default · permission (bash)</div>
        <div class="stage-stamp">SHIPS</div>
        ${gbubble({ mode: 'permission', toolName: 'Bash', command: 'brew update && brew upgrade' })}
      </div>
      <div class="desktop-stage">
        <div class="stage-label">compact · no body</div>
        <div class="stage-stamp">TIGHT</div>
        ${gbubble({ mode: 'permission', toolName: 'Bash', compact: true,
                    suggestions: [
                      { label: 'Allow Session', kbd: '⌘⇧S' },
                      { label: 'Always allow `brew update:*`', kbd: null }
                    ] })}
      </div>
      <div class="desktop-stage">
        <div class="stage-label">permission · edit</div>
        ${gbubble({ mode: 'permission', toolName: 'Edit',
                    command: 'edit src/components/Pet.tsx\n+ add state transition timer\n- remove legacy SVG eye tracker',
                    suggestions: [
                      { label: 'Allow Edit in src/', kbd: '⌘⇧S' },
                      { label: 'Auto-accept edits', kbd: null }
                    ] })}
      </div>
      <div class="desktop-stage">
        <div class="stage-label">plan review</div>
        ${gbubble({ mode: 'plan', toolName: 'Plan' })}
      </div>
      <div class="desktop-stage" style="grid-column: 1 / -1;">
        <div class="stage-label">elicitation · needs input</div>
        <div class="stage-stamp">FORM</div>
        ${gbubble({ mode: 'elicitation', toolName: 'Ask',
                    elicit: {
                      section: 'Session goal',
                      question: 'What would you like to focus on in this session?',
                      hint: 'Choose one option',
                      options: [
                        { title: 'Code review', desc: 'Review recent changes and provide feedback on the implementation.', selected: false },
                        { title: 'Bug fixing', desc: 'Investigate and fix a specific bug or unexpected behavior.', selected: true },
                        { title: 'New feature', desc: 'Plan and implement a new feature or enhancement.', selected: false },
                      ]
                    } })}
      </div>
    </section>
  `);

  // ---------- Section 07 — Chat bubble (future) ----------
  page.insertAdjacentHTML('beforeend', `
    <div class="section-label"><span class="n">07</span> Chat bubble · future</div>
    <h2 class="heading">Chat with squib.</h2>
    <div class="subhead">
      Future surface: click the pet to open a chat window that sits next to them on the edge. Same liquid-glass language as the permission card;
      pill input with a send/stop affordance and model selector on the right. Tool calls render as inline chips with a green check when done.
    </div>
    <div class="desktop-stage mountain" style="min-height: 620px; justify-content:center;">
      <div class="stage-label">chat · pet attached</div>
      <div class="stage-stamp">FUTURE</div>
      <div class="chat-stage-row">
        ${gchat({})}
        <div class="crab-holder">${crab({ mini: 'mini-peek', size: 110, flip: 'h' })}</div>
      </div>
    </div>
  `);

  // ---------- Section 08 — Next steps ----------
  page.insertAdjacentHTML('beforeend', `
    <div class="section-label"><span class="n">08</span> Next steps</div>
    <div class="note">
      <b>Ship path:</b>
      (1) Export each crab state as APNG @2x, transparent, 3–5s loop.
      (2) Drop in <span style="font-family:var(--mono);">Sources/squib/Resources/</span>.
      (3) Port the glass bubble CSS/HTML into <span style="font-family:var(--mono);">BubbleWindow.swift</span>'s <span style="font-family:var(--mono);">bubbleHTML</span>. JS bridge unchanged — <span style="font-family:var(--mono);">loadPermission(data)</span>, <span style="font-family:var(--mono);">post({type,value})</span>.
      (4) Macos 26 <span style="font-family:var(--mono);">NSVisualEffectView</span> w/ <span style="font-family:var(--mono);">.hudWindow</span> material as the window; the inner HTML uses <span style="font-family:var(--mono);">backdrop-filter</span> as fallback for browser previews.
      (5) Chat surface (section 07) is a later milestone — separate window attached to pet position.
      <br><br>
      <b>Open questions:</b>
      • Compact or full permission card as default?
      • Keep per-tool pill colors (Bash = warm orange, Edit = blue) or unify to a single neutral?
      • Chat: does the pet detach and float next to the chat window, or anchor to a fixed edge?
    </div>
  `);

  // ---------- Tweaks ----------
  buildTweaks();
})();

// ---------------- TWEAKS ---------------- //

function buildTweaks() {
  const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
    "bodyColor": "clay",
    "accent": "rust",
    "inkWeight": "felt",
    "texture": true,
    "theme": "light"
  }/*EDITMODE-END*/;

  const state = { ...TWEAK_DEFAULTS, ...(loadLocal() || {}) };

  const bodyMap = {
    clay:   { soft: '#e39b7b', name: 'clay'   },
    bone:   { soft: '#ddd2b8', name: 'bone'   },
    moss:   { soft: '#9bab7f', name: 'moss'   },
    slate:  { soft: '#8a96a3', name: 'slate'  },
    terra:  { soft: '#c97a55', name: 'terra'  },
  };
  const accentMap = {
    rust:      { c: '#c24d2c', name: 'rust'      },
    stamp:     { c: '#d6301c', name: 'stamp red' },
    highlight: { c: '#e8c547', name: 'highlight' },
    navy:      { c: '#2a4a7a', name: 'navy ink'  },
    riso:      { c: '#ff5f8a', name: 'riso pink' },
  };
  const weightMap = {
    pen:    { w: 1.4, soft: 1.0, name: 'pen · 1.4px'    },
    felt:   { w: 2.2, soft: 1.2, name: 'felt · 2.2px'   },
    marker: { w: 3.4, soft: 1.6, name: 'marker · 3.4px' },
  };

  function apply() {
    const b = bodyMap[state.bodyColor] || bodyMap.clay;
    const a = accentMap[state.accent] || accentMap.rust;
    const w = weightMap[state.inkWeight] || weightMap.felt;
    const root = document.documentElement;
    root.style.setProperty('--accent-soft', b.soft);
    root.style.setProperty('--accent', a.c);
    root.style.setProperty('--ink-w', w.w);
    root.style.setProperty('--ink-w-soft', w.soft);
    root.dataset.theme = state.theme;

    document.body.classList.toggle('paper-texture', !!state.texture);

    set('chip-shell', 'background: ' + b.soft);
    set('chip-shell-hex', null, b.name);
    set('hex-shell', null, b.name);
    set('chip-ink', 'background: var(--ink)');
    set('chip-accent', 'background: ' + a.c);
    set('chip-accent-hex', null, a.name);
    set('hex-accent', null, a.c);
    set('chip-weight', null, w.name);

    document.querySelectorAll('[data-tw]').forEach(btn => {
      const [k, v] = btn.dataset.tw.split(':');
      btn.setAttribute('aria-pressed', String(state[k]) == v ? 'true' : 'false');
    });

    persist();
  }
  function set(id, style, text) {
    const el = document.getElementById(id); if (!el) return;
    if (style !== null && style !== undefined) el.setAttribute('style', style);
    if (text !== undefined && text !== null) el.textContent = text;
  }
  function persist() {
    try { localStorage.setItem('squib.tweaks', JSON.stringify(state)); } catch (e) {}
    if (window.parent !== window) {
      window.parent.postMessage({ type: '__edit_mode_set_keys', edits: state }, '*');
    }
  }
  function loadLocal() {
    try { return JSON.parse(localStorage.getItem('squib.tweaks') || 'null'); } catch (e) { return null; }
  }

  const toggle = document.createElement('button');
  toggle.className = 'tweaks-toggle';
  toggle.textContent = 'Tweaks ▸';
  toggle.onclick = () => panel.classList.toggle('open');
  document.body.appendChild(toggle);

  const panel = document.createElement('aside');
  panel.className = 'tweaks';
  panel.innerHTML = `
    <div class="tw-title"><span>Tweaks</span><span class="dot"></span></div>

    <div class="tw-row">
      <label>Body color</label>
      <div class="tw-buttons">
        ${Object.entries(bodyMap).map(([k, v]) => `
          <button class="tw-btn" data-tw="bodyColor:${k}">
            <span class="c" style="background:${v.soft}"></span>${v.name}
          </button>`).join('')}
      </div>
    </div>

    <div class="tw-row">
      <label>Accent</label>
      <div class="tw-buttons">
        ${Object.entries(accentMap).map(([k, v]) => `
          <button class="tw-btn" data-tw="accent:${k}">
            <span class="c" style="background:${v.c}"></span>${v.name}
          </button>`).join('')}
      </div>
    </div>

    <div class="tw-row">
      <label>Ink weight</label>
      <div class="tw-buttons">
        ${Object.entries(weightMap).map(([k, v]) => `
          <button class="tw-btn" data-tw="inkWeight:${k}">${v.name}</button>`).join('')}
      </div>
    </div>

    <div class="tw-row">
      <label>Paper texture</label>
      <div class="tw-buttons">
        <button class="tw-btn" data-tw="texture:true">On</button>
        <button class="tw-btn" data-tw="texture:false">Off</button>
      </div>
    </div>

    <div class="tw-row">
      <label>Theme (pet sheet)</label>
      <div class="tw-buttons">
        <button class="tw-btn" data-tw="theme:light">Paper</button>
        <button class="tw-btn" data-tw="theme:dark">Night</button>
      </div>
    </div>
  `;
  document.body.appendChild(panel);

  panel.addEventListener('click', e => {
    const btn = e.target.closest('[data-tw]');
    if (!btn) return;
    const [k, v] = btn.dataset.tw.split(':');
    state[k] = (v === 'true') ? true : (v === 'false') ? false : v;
    apply();
  });

  window.addEventListener('message', (ev) => {
    const d = ev.data || {};
    if (d.type === '__activate_edit_mode') panel.classList.add('open');
    if (d.type === '__deactivate_edit_mode') panel.classList.remove('open');
  });
  if (window.parent !== window) {
    window.parent.postMessage({ type: '__edit_mode_available' }, '*');
  }

  apply();
}
