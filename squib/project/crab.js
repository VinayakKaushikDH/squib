/* Squib the crab — original zine-style SVG component.
 * Renders a square-carapace crab with configurable pose + state.
 * All strokes reference the --ink variable so weight/color can be re-themed globally.
 */

/**
 * @param {object} opts
 * @param {string} opts.state         - idle|thinking|working|sleeping|error|attention|idle-reading
 * @param {string} [opts.mini]        - mini-idle|mini-alert|mini-peek (renders edge-peek variant)
 * @param {number} [opts.size=200]    - render size in px
 * @param {string} [opts.flip]        - 'h' to horizontally flip (for mirrorable edge peeks)
 * @returns {string} SVG markup
 */
function crab(opts) {
  const { state = 'idle', mini = null, size = 200, flip = null } = opts || {};
  if (mini) return crabMini({ mini, size, flip });

  // Per-state geometry offsets (head tilt, eye pos, mouth, body bob freq)
  const s = state;
  const bodyClass = `crab-body state-${s}`;
  const eyeTilt = s === 'thinking' ? -3 : s === 'sleeping' ? 0 : s === 'attention' ? -4 : 0;

  // --- Eyes ---
  let eyes = '';
  if (s === 'sleeping') {
    eyes = `
      <path class="eye-closed" d="M 34 50 q 6 4 12 0" />
      <path class="eye-closed" d="M 54 50 q 6 4 12 0" />`;
  } else if (s === 'error') {
    eyes = `
      <g class="eye-x">
        <line x1="34" y1="46" x2="44" y2="56" />
        <line x1="44" y1="46" x2="34" y2="56" />
      </g>
      <g class="eye-x">
        <line x1="56" y1="46" x2="66" y2="56" />
        <line x1="66" y1="46" x2="56" y2="56" />
      </g>`;
  } else {
    // Standard pupils — stalked look with small dark rectangles, zine style.
    const pupilY = 46 + eyeTilt;
    const widthL = s === 'attention' ? 4.5 : 3.5;
    const widthR = s === 'attention' ? 4.5 : 3.5;
    const heightE = s === 'attention' ? 8 : 6;
    eyes = `
      <g class="eye eye-l">
        <rect x="${39 - widthL/2}" y="${pupilY - heightE/2}" width="${widthL}" height="${heightE}" rx="0.6" fill="var(--ink)" />
      </g>
      <g class="eye eye-r">
        <rect x="${61 - widthR/2}" y="${pupilY - heightE/2}" width="${widthR}" height="${heightE}" rx="0.6" fill="var(--ink)" />
      </g>`;
  }

  // --- Mouth (grumpy personality: flat or slight downturn) ---
  let mouth = '';
  if (s === 'happy' || s === 'attention') {
    mouth = `<path class="mouth" d="M 44 64 q 6 3 12 0" />`;
  } else if (s === 'sleeping') {
    mouth = `<path class="mouth" d="M 46 64 q 4 2 8 0" />`; // tiny
  } else if (s === 'error') {
    mouth = `<path class="mouth" d="M 44 66 q 6 -3 12 0" />`; // frown
  } else if (s === 'working') {
    mouth = `<rect class="mouth-flat" x="45" y="63" width="10" height="2" rx="0.5" />`;
  } else {
    // grumpy default — short flat downturn
    mouth = `<path class="mouth" d="M 44 65 q 6 -1 12 0" />`;
  }

  // --- Props per state (thought bubble, ZZZ, etc.) ---
  let props = '';
  if (s === 'thinking') {
    props = `
      <g class="thought" transform="translate(70 18)">
        <circle cx="2" cy="14" r="2" fill="var(--ink)" />
        <circle cx="7" cy="8" r="3" fill="var(--ink)" />
        <ellipse cx="16" cy="0" rx="10" ry="7" fill="var(--paper)" stroke="var(--ink)" stroke-width="var(--ink-w)" />
        <text x="16" y="3" text-anchor="middle" font-family="var(--mono)" font-size="9" fill="var(--ink)" font-weight="600">?</text>
      </g>`;
  } else if (s === 'sleeping') {
    props = `
      <g class="zzz">
        <text x="70" y="30" font-family="var(--mono)" font-size="12" fill="var(--ink)" font-weight="600" class="zzz-1">z</text>
        <text x="78" y="20" font-family="var(--mono)" font-size="14" fill="var(--ink)" font-weight="600" class="zzz-2">z</text>
        <text x="88" y="8"  font-family="var(--mono)" font-size="17" fill="var(--ink)" font-weight="700" class="zzz-3">Z</text>
      </g>`;
  } else if (s === 'error') {
    props = `
      <g class="err-mark">
        <line x1="72" y1="18" x2="72" y2="28" stroke="var(--accent)" stroke-width="3.2" stroke-linecap="round" />
        <circle cx="72" cy="33" r="1.8" fill="var(--accent)" />
      </g>`;
  } else if (s === 'attention') {
    props = `
      <g class="attn">
        <line x1="72" y1="14" x2="72" y2="26" stroke="var(--accent)" stroke-width="3.2" stroke-linecap="round" />
        <circle cx="72" cy="31" r="1.8" fill="var(--accent)" />
      </g>`;
  } else if (s === 'working') {
    props = `
      <g class="type-sparks">
        <rect x="14" y="24" width="2" height="2" fill="var(--accent)" class="spark s1"/>
        <rect x="12" y="30" width="2" height="2" fill="var(--accent)" class="spark s2"/>
        <rect x="18" y="30" width="2" height="2" fill="var(--accent)" class="spark s3"/>
      </g>`;
  } else if (s === 'idle-reading') {
    // Crab holding a tiny zine/notebook
    props = `
      <g class="zine" transform="translate(30 60)">
        <rect x="0" y="0" width="14" height="10" fill="var(--paper)" stroke="var(--ink)" stroke-width="var(--ink-w)" />
        <line x1="7" y1="0" x2="7" y2="10" stroke="var(--ink)" stroke-width="var(--ink-w)" />
        <line x1="2" y1="3" x2="5" y2="3" stroke="var(--ink)" stroke-width="1" />
        <line x1="2" y1="6" x2="5" y2="6" stroke="var(--ink)" stroke-width="1" />
        <line x1="9" y1="3" x2="12" y2="3" stroke="var(--ink)" stroke-width="1" />
        <line x1="9" y1="6" x2="12" y2="6" stroke="var(--ink)" stroke-width="1" />
      </g>`;
  }

  // --- Body: square-ish carapace, zine-style rect with subtle wobble via path ---
  // Using a path rather than rect so linecap/linejoin reads hand-drawn.
  const body = `
    <path class="carapace" d="
      M 20 34
      L 80 34
      L 82 70
      L 18 70
      Z" />
    <!-- carapace ridge (shell detail) -->
    <path class="ridge" d="M 24 40 L 76 40" />
    <path class="ridge" d="M 26 44 L 32 44 M 50 44 L 50 44 M 68 44 L 74 44" opacity="0.5" />`;

  // --- Claws: up-front, grumpy defensive pose; per-state animation classes ---
  const clawClass = `claw claw-${s}`;
  // Left claw
  const claws = `
    <g class="${clawClass} claw-l">
      <path class="claw-arm" d="M 20 58 L 10 58 L 6 52" />
      <path class="claw-top" d="M 2 46 L 10 46 L 12 52 L 4 52 Z" />
      <path class="claw-bot" d="M 2 54 L 10 54 L 12 58 L 4 58 Z" />
    </g>
    <g class="${clawClass} claw-r">
      <path class="claw-arm" d="M 80 58 L 90 58 L 94 52" />
      <path class="claw-top" d="M 98 46 L 90 46 L 88 52 L 96 52 Z" />
      <path class="claw-bot" d="M 98 54 L 90 54 L 88 58 L 96 58 Z" />
    </g>`;

  // --- Legs: short walker legs under body ---
  const legs = `
    <g class="legs legs-${s}">
      <path class="leg" d="M 34 70 L 34 80 L 30 84" />
      <path class="leg" d="M 46 70 L 46 82 L 42 86" />
      <path class="leg" d="M 54 70 L 54 82 L 58 86" />
      <path class="leg" d="M 66 70 L 66 80 L 70 84" />
    </g>`;

  // Shadow under body (paper-stamp feel, soft)
  const shadow = `<ellipse class="shadow" cx="50" cy="92" rx="26" ry="2.2" />`;

  return `
    <svg viewBox="0 0 100 110" class="${bodyClass}" width="${size}" height="${size * 1.1}" xmlns="http://www.w3.org/2000/svg">
      <g class="bob">
        ${shadow}
        ${legs}
        ${claws}
        ${body}
        ${eyes}
        ${mouth}
        ${props}
      </g>
    </svg>`;
}

/** Mini-mode: crab peeking from right edge. Use transform for left/top/bottom. */
function crabMini({ mini, size = 160, flip = null }) {
  const s = mini;
  let eyes = '';
  let props = '';

  if (s === 'mini-alert') {
    eyes = `
      <rect x="52" y="36" width="5" height="9" fill="var(--ink)" />
      <rect x="64" y="36" width="5" height="9" fill="var(--ink)" />`;
    props = `
      <g class="attn">
        <line x1="22" y1="20" x2="22" y2="34" stroke="var(--accent)" stroke-width="4" stroke-linecap="round" />
        <circle cx="22" cy="40" r="2.3" fill="var(--accent)" />
      </g>`;
  } else if (s === 'mini-peek') {
    eyes = `
      <rect x="56" y="40" width="4" height="7" fill="var(--ink)" />
      <rect x="68" y="40" width="4" height="7" fill="var(--ink)" />`;
    props = `
      <g class="peek-question" transform="translate(30 30)">
        <text font-family="var(--mono)" font-size="14" fill="var(--ink)" font-weight="700">?</text>
      </g>`;
  } else {
    // mini-idle — neutral peek, one eye visible leaning
    eyes = `
      <rect x="58" y="42" width="4" height="6" fill="var(--ink)" />
      <rect x="70" y="42" width="4" height="6" fill="var(--ink)" />`;
  }

  // Body peeks from right (user sees left portion of crab)
  const body = `
    <g class="mini-body bob-mini">
      <!-- claw poking out -->
      <path class="claw-arm" d="M 40 55 L 32 55 L 28 50" />
      <path class="claw-top" d="M 24 44 L 32 44 L 34 50 L 26 50 Z" />
      <path class="claw-bot" d="M 24 52 L 32 52 L 34 55 L 26 55 Z" />
      <!-- half carapace -->
      <path class="carapace" d="M 40 30 L 100 30 L 100 68 L 42 68 Z" />
      <path class="ridge" d="M 44 36 L 96 36" />
      <!-- legs -->
      <path class="leg" d="M 56 68 L 56 80 L 52 82" />
      <path class="leg" d="M 70 68 L 70 80 L 66 82" />
      ${eyes}
      <!-- small flat mouth -->
      <path class="mouth" d="M 60 58 q 6 -1 12 0" />
    </g>
    <!-- edge shadow bar (hint of wall) -->
    <rect x="100" y="0" width="12" height="110" fill="var(--edge)" />
    ${props}`;

  const transform = flip === 'h' ? 'scale(-1,1) translate(-112 0)' : '';
  return `
    <svg viewBox="0 0 112 110" width="${size * 1.12}" height="${size * 1.1}" class="crab-mini state-${s}" xmlns="http://www.w3.org/2000/svg">
      <g transform="${transform}">
        ${body}
      </g>
    </svg>`;
}

window.crab = crab;
