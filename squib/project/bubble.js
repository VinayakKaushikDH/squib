// Renders Apple Liquid Glass bubble + chat instances for preview.
// Mirrors the JS contract from the brief (loadPermission payload).

function gbubble(opts) {
  const {
    mode = 'permission',       // permission | plan | elicitation | default
    toolName = 'Bash',
    command = "ls -la src/",
    sessionFolder = 'self-service-frontend',
    sessionShortId = '969',
    suggestions = [
      { label: 'Allow Session', kbd: '⌘⇧S' },
      { label: 'Always allow `brew update:*`', kbd: null },
    ],
    elicit = null,
    compact = false,           // compact = tight permission card (from screenshot 2)
  } = opts || {};

  const pillClass = toolName.toLowerCase();

  let title = 'Permission Request';
  if (mode === 'plan')        title = 'Plan Review';
  if (mode === 'elicitation') title = 'Needs Input';
  if (mode === 'default')     title = toolName;

  const head = `
    <div class="ghead">
      <div>
        <div class="htitle">${title}</div>
        <div class="hmeta">${sessionFolder}<span class="dot">·</span><span class="sid">#${sessionShortId}</span></div>
      </div>
      <span class="gpill ${pillClass}">${toolName}</span>
    </div>`;

  // Body
  let body = '';
  if (mode === 'elicitation') {
    const q = (elicit && elicit.question) || 'What would you like to focus on in this session?';
    const hint = (elicit && elicit.hint) || 'Choose one option';
    const section = (elicit && elicit.section) || 'Session goal';
    const opts2 = (elicit && elicit.options) || [
      { title: 'Code review', desc: 'Review recent changes and provide feedback on the implementation.', selected: false },
      { title: 'Bug fixing', desc: 'Investigate and fix a specific bug or unexpected behavior.', selected: false },
      { title: 'New feature', desc: 'Plan and implement a new feature or enhancement.', selected: false },
    ];
    body = `
      <div class="gform">
        <div class="section-lbl">${escapeHtml(section)}</div>
        <div class="q">${escapeHtml(q)}</div>
        <div class="hint">${escapeHtml(hint)}</div>
        ${opts2.map(o => `
          <div class="gopt ${o.selected ? 'sel' : ''}">
            <div class="radio"></div>
            <div class="otext">
              <div class="ot">${escapeHtml(o.title)}</div>
              <div class="od">${escapeHtml(o.desc)}</div>
            </div>
          </div>`).join('')}
      </div>`;
  } else if (mode === 'plan') {
    body = `
      <div class="gbody">
        <div class="gcmd"><span class="prompt">›</span> Migrate auth to OAuth2
1. Add <span style="color:var(--glass-accent)">oauth2-proxy</span> service
2. Update <span style="color:var(--glass-accent)">auth.ts</span> client
3. Add callback routes in <span style="color:var(--glass-accent)">server/api.ts</span>
4. Migrate existing JWT tokens
5. Remove legacy <span style="color:var(--glass-accent)">sessionStore.ts</span></div>
      </div>`;
  } else if (!compact) {
    body = `
      <div class="gbody">
        <div class="gcmd"><span class="prompt">$ </span>${escapeHtml(command)}</div>
      </div>`;
  }
  // compact mode omits the body entirely (matches screenshot 2)

  // Actions
  let actions;
  if (mode === 'elicitation') {
    actions = `
      <div class="gactions">
        <button class="gbtn">Go to Terminal <span class="kbd">[⌘⇧N]</span></button>
        <button class="gbtn primary">Submit Answer <span class="kbd">[⌘⇧Y]</span></button>
      </div>`;
  } else if (mode === 'plan') {
    actions = `
      <div class="gactions">
        <button class="gbtn">Go to Terminal <span class="kbd">[⌘⇧N]</span></button>
        <button class="gbtn primary">Approve <span class="kbd">[⌘⇧Y]</span></button>
      </div>`;
  } else {
    actions = `
      <div class="gactions">
        <button class="gbtn">Deny <span class="kbd">[⌘⇧N]</span></button>
        <button class="gbtn primary">Allow <span class="kbd">[⌘⇧Y]</span></button>
      </div>`;
  }

  // Suggestions (only permission mode)
  const sugs = (mode === 'permission' && suggestions.length)
    ? `<div class="gsuggest">
         ${suggestions.map(s => `
           <button class="gsug">
             <span>${escapeHtml(s.label)}</span>
             ${s.kbd ? `<span class="kbd">[${s.kbd}]</span>` : ''}
           </button>`).join('')}
       </div>`
    : '';

  const widthClass = (mode === 'elicitation') ? ' wide' : '';

  return `
    <div class="gcard glass-scope enter${widthClass}">
      ${head}
      ${body}
      ${actions}
      ${sugs}
    </div>`;
}

/** Future: chat bubble alongside the pet. */
function gchat(opts) {
  const { messages = defaultMessages() } = opts || {};

  const ic = {
    close: `<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>`,
    edit: `<svg viewBox="0 0 24 24"><path d="M4 20h4L18 10l-4-4L4 16v4z"/><path d="M14 6l4 4"/></svg>`,
    expand: `<svg viewBox="0 0 24 24"><path d="M4 14v6h6M20 10V4h-6M4 20l7-7M20 4l-7 7"/></svg>`,
    plus: `<svg viewBox="0 0 24 24" stroke="currentColor" fill="none" stroke-width="2" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>`,
    stop: `<svg viewBox="0 0 24 24"><rect x="7" y="7" width="10" height="10" rx="1"/></svg>`,
  };

  return `
    <div class="gcard glass-scope gchat enter">
      <div class="chead">
        <div class="chead-left">
          <div class="cbtn-icon" title="close">${ic.close}</div>
        </div>
        <div class="ctitle"><span class="livedot"></span>squib · claude-code</div>
        <div class="chead-right">
          <div class="cbtn-icon" title="new">${ic.edit}</div>
          <div class="cbtn-icon" title="expand">${ic.expand}</div>
        </div>
      </div>
      <div class="cbody">
        ${messages.map(m => renderMsg(m)).join('')}
      </div>
      <div class="cfoot">
        <div class="cinput">
          <div class="plus">${ic.plus}</div>
          <div class="ph">Ask squib…</div>
          <div class="mode">claude-sonnet</div>
          <div class="send">${ic.stop}</div>
        </div>
      </div>
    </div>`;
}

function renderMsg(m) {
  if (m.type === 'tool') {
    return `<div class="cmsg assistant"><div class="ctool">${escapeHtml(m.name)}<span class="done">✓</span></div></div>`;
  }
  if (m.role === 'user') {
    return `<div class="cmsg user"><div class="cbubble">${escapeHtml(m.text)}</div></div>`;
  }
  return `<div class="cmsg assistant">
    <div class="cbubble"><span class="aglyph">✦</span>${escapeHtml(m.text)}</div>
  </div>`;
}

function defaultMessages() {
  return [
    { role: 'user', text: 'can you check why the login is redirecting twice?' },
    { role: 'assistant', text: 'Looking into it — scanning the auth flow.' },
    { type: 'tool', name: 'Read · auth.ts' },
    { type: 'tool', name: 'Grep · redirect' },
    { role: 'assistant', text: "Found it. `useEffect` in `LoginShell.tsx` fires a second redirect when the session refreshes. Want me to patch it?" },
    { role: 'user', text: 'yeah, patch it' },
  ];
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

window.gbubble = gbubble;
window.gchat = gchat;
