// Helmy's marking tools, injected into the page in the Preview panel (the
// built-in browser and Chromium alike). Marks are drawn on the page in a
// shadow root of their own, so the page's styles never reach them; what each
// mark is goes back to Helmy as JSON, through whichever bridge the engine
// gives: Chromium's `helmyAnnotate` binding, or WebKit's `Helmy` channel.
(() => {
  if (window.__helmyAnnotate) return;

  const post = (message) => {
    const text = JSON.stringify(message);
    if (typeof window.helmyAnnotate === 'function') window.helmyAnnotate(text);
    else if (window.Helmy && window.Helmy.postMessage) window.Helmy.postMessage(text);
  };

  // The layer the marks are drawn in, above the page.
  const host = document.createElement('div');
  host.setAttribute('data-helmy-annotate', '');
  host.style.cssText =
    'position:fixed;inset:0;z-index:2147483647;pointer-events:none;';
  const root = host.attachShadow({ mode: 'open' });
  root.innerHTML = `
    <style>
      .box { position: fixed; border: 2px solid #2563eb; background: rgba(37,99,235,.10);
             border-radius: 3px; pointer-events: none; box-sizing: border-box; }
      .hover { border-style: dashed; background: rgba(37,99,235,.06); }
      .badge { position: fixed; min-width: 18px; height: 18px; padding: 0 5px; border-radius: 9px;
               background: #2563eb; color: #fff; font: 600 11px/18px -apple-system, system-ui, sans-serif;
               text-align: center; pointer-events: none; box-shadow: 0 1px 3px rgba(0,0,0,.3); }
      .catch { position: fixed; inset: 0; pointer-events: auto; cursor: crosshair; }
      canvas { position: fixed; inset: 0; pointer-events: none; }
      .live { position: fixed; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); }
    </style>
    <canvas></canvas><div class="marks"></div><div class="hover box" hidden></div>
    <div class="live" aria-live="polite"></div>`;
  const marksLayer = root.querySelector('.marks');
  const hoverBox = root.querySelector('.hover');
  const live = root.querySelector('.live');
  const canvas = root.querySelector('canvas');
  const ink = canvas.getContext('2d');

  let mode = null; // 'pick', 'region', 'draw', or null (off)
  let catcher = null;
  let marks = [];
  let focused = null; // the element the keyboard is on, in pick mode
  let drag = null;
  let strokes = []; // finished strokes, each a list of points
  let stroke = null;

  const sizeCanvas = () => {
    const r = window.devicePixelRatio || 1;
    canvas.width = innerWidth * r;
    canvas.height = innerHeight * r;
    canvas.style.width = innerWidth + 'px';
    canvas.style.height = innerHeight + 'px';
    ink.setTransform(r, 0, 0, r, 0, 0);
    paint();
  };

  const paint = () => {
    ink.clearRect(0, 0, innerWidth, innerHeight);
    ink.strokeStyle = '#ef4444';
    ink.lineWidth = 3;
    ink.lineCap = ink.lineJoin = 'round';
    for (const s of [...strokes.flat(), ...(stroke ? [stroke] : [])]) {
      ink.beginPath();
      s.forEach((p, i) => (i ? ink.lineTo(p.x, p.y) : ink.moveTo(p.x, p.y)));
      ink.stroke();
    }
    for (const m of marks) {
      if (m.kind !== 'drawing') continue;
      const b = m.rect;
      place(m.badgeEl, b.x - 9, b.y - 9);
    }
  };

  const place = (el, x, y) => {
    el.style.left = Math.max(2, x) + 'px';
    el.style.top = Math.max(2, y) + 'px';
  };

  // What an element is, for the agent.

  const ours = (el) => el === host || host.contains(el);

  const selectorOf = (el) => {
    if (!(el instanceof Element)) return null;
    const esc = (s) => (window.CSS && CSS.escape ? CSS.escape(s) : s);
    const parts = [];
    let node = el;
    while (node && node.nodeType === 1 && parts.length < 6) {
      if (node.id && document.querySelectorAll('#' + esc(node.id)).length === 1) {
        parts.unshift('#' + esc(node.id));
        break;
      }
      const test = node.getAttribute('data-testid');
      if (test) {
        parts.unshift(`[data-testid="${test}"]`);
        break;
      }
      let part = node.tagName.toLowerCase();
      const parent = node.parentElement;
      if (parent) {
        const same = [...parent.children].filter((c) => c.tagName === node.tagName);
        if (same.length > 1) part += `:nth-of-type(${same.indexOf(node) + 1})`;
      }
      parts.unshift(part);
      if (node === document.body) break;
      node = parent;
    }
    return parts.join(' > ');
  };

  // The component and source file that drew it, where the page is a
  // development build that keeps them: React (before 19), Vue 3, Svelte.
  const sourceOf = (el) => {
    try {
      const fiberKey = Object.keys(el).find((k) => k.startsWith('__reactFiber$'));
      if (fiberKey) {
        for (let f = el[fiberKey]; f; f = f.return) {
          const name = f.type && (f.type.displayName || f.type.name);
          if (typeof f.type === 'function' || (f.type && typeof f.type === 'object')) {
            const s = f._debugSource;
            return {
              component: name || null,
              file: s ? s.fileName : null,
              line: s ? s.lineNumber : null,
              column: s ? s.columnNumber : null,
            };
          }
        }
      }
      for (let n = el; n; n = n.parentElement) {
        const vue = n.__vueParentComponent;
        if (vue && vue.type) {
          return { component: vue.type.name || vue.type.__name || null, file: vue.type.__file || null, line: null, column: null };
        }
        const svelte = n.__svelte_meta;
        if (svelte && svelte.loc) {
          return { component: null, file: svelte.loc.file, line: svelte.loc.line + 1, column: svelte.loc.column };
        }
      }
    } catch (_) { /* a page's own objects can throw; the source is then unknown */ }
    return null;
  };

  const STYLES = ['display', 'position', 'width', 'height', 'margin', 'padding', 'color',
    'background-color', 'font-family', 'font-size', 'font-weight', 'line-height',
    'border', 'border-radius', 'gap', 'opacity'];

  const describe = (el) => {
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    const html = el.outerHTML || '';
    return {
      tag: el.tagName.toLowerCase(),
      selector: selectorOf(el),
      role: el.getAttribute('role') || null,
      label: (el.getAttribute('aria-label') || el.getAttribute('alt') || el.getAttribute('title') || '').trim() || null,
      text: (el.innerText || el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 300),
      html: html.length > 4000 ? html.slice(0, 4000) + '…' : html,
      styles: Object.fromEntries(STYLES.map((p) => [p, cs.getPropertyValue(p)]).filter(([, v]) => v && v !== 'normal' && v !== 'none' && v !== 'auto' && v !== '0px')),
      source: sourceOf(el),
      rect: { x: r.x, y: r.y, width: r.width, height: r.height },
    };
  };

  const name = (el) => {
    const d = el.getAttribute('aria-label') || (el.innerText || '').trim().split('\n')[0].slice(0, 40);
    return `${el.tagName.toLowerCase()}${d ? ' "' + d + '"' : ''}`;
  };

  // Marks.

  const addMark = (mark) => {
    mark.n = (marks.length ? marks[marks.length - 1].n : 0) + 1;
    const r = mark.rect;
    if (mark.kind !== 'drawing') {
      mark.boxEl = document.createElement('div');
      mark.boxEl.className = 'box';
      Object.assign(mark.boxEl.style, { left: r.x + 'px', top: r.y + 'px', width: r.width + 'px', height: r.height + 'px' });
      marksLayer.appendChild(mark.boxEl);
    }
    mark.badgeEl = document.createElement('div');
    mark.badgeEl.className = 'badge';
    mark.badgeEl.textContent = mark.n;
    marksLayer.appendChild(mark.badgeEl);
    place(mark.badgeEl, r.x - 9, r.y - 9);
    marks.push(mark);
    const { boxEl, badgeEl, ...out } = mark;
    post({ type: 'mark', mark: out });
    live.textContent = `Marked ${mark.n}: ${mark.summary}`;
  };

  const removeMark = (n) => {
    const m = marks.find((x) => x.n === n);
    if (!m) return;
    m.boxEl && m.boxEl.remove();
    m.badgeEl.remove();
    if (m.kind === 'drawing') strokes = strokes.filter((s) => s !== m.strokes);
    marks = marks.filter((x) => x !== m);
    paint();
  };

  // Input, while marking.

  const pointIn = (e) => ({ x: e.clientX, y: e.clientY });
  const under = (e) => {
    catcher.style.pointerEvents = 'none';
    const el = document.elementFromPoint(e.clientX, e.clientY);
    catcher.style.pointerEvents = 'auto';
    return el && !ours(el) ? el : null;
  };

  const showHover = (el) => {
    if (!el) return (hoverBox.hidden = true);
    const r = el.getBoundingClientRect();
    hoverBox.hidden = false;
    Object.assign(hoverBox.style, { left: r.x + 'px', top: r.y + 'px', width: r.width + 'px', height: r.height + 'px' });
  };

  const pick = (el) => {
    if (!el) return;
    const d = describe(el);
    addMark({ kind: 'element', summary: name(el), rect: d.rect, element: d });
  };

  const regionOf = (a, b) => ({
    x: Math.min(a.x, b.x), y: Math.min(a.y, b.y),
    width: Math.abs(a.x - b.x), height: Math.abs(a.y - b.y),
  });

  // The elements inside a region: the outermost ones wholly within it.
  const inside = (rect) => {
    const found = [];
    for (const el of document.body.querySelectorAll('*')) {
      if (ours(el) || found.some((f) => f.contains(el))) continue;
      const r = el.getBoundingClientRect();
      if (r.width < 4 || r.height < 4) continue;
      if (r.x >= rect.x && r.y >= rect.y && r.right <= rect.x + rect.width && r.bottom <= rect.y + rect.height) {
        found.push(el);
        if (found.length >= 20) break;
      }
    }
    return found;
  };

  const down = (e) => {
    e.preventDefault();
    const p = pointIn(e);
    if (mode === 'pick') pick(under(e));
    else if (mode === 'region') drag = { from: p, to: p };
    else if (mode === 'draw') { stroke = [p]; paint(); }
  };
  const move = (e) => {
    const p = pointIn(e);
    if (mode === 'pick') showHover(under(e));
    else if (mode === 'region' && drag) {
      drag.to = p;
      const r = regionOf(drag.from, drag.to);
      hoverBox.hidden = false;
      Object.assign(hoverBox.style, { left: r.x + 'px', top: r.y + 'px', width: r.width + 'px', height: r.height + 'px' });
    } else if (mode === 'draw' && stroke) { stroke.push(p); paint(); }
  };
  const up = () => {
    if (mode === 'region' && drag) {
      const r = regionOf(drag.from, drag.to);
      drag = null;
      hoverBox.hidden = true;
      if (r.width < 6 || r.height < 6) return;
      const els = inside(r);
      addMark({
        kind: 'region',
        summary: `region, ${els.length} element${els.length === 1 ? '' : 's'} inside`,
        rect: r,
        elements: els.map(describe),
      });
    } else if (mode === 'draw' && stroke) {
      const s = stroke;
      stroke = null;
      if (s.length < 2) return paint();
      const xs = s.map((p) => p.x), ys = s.map((p) => p.y);
      const r = { x: Math.min(...xs), y: Math.min(...ys), width: Math.max(...xs) - Math.min(...xs), height: Math.max(...ys) - Math.min(...ys) };
      const strokeGroup = [s];
      strokes.push(strokeGroup);
      const els = inside(r);
      addMark({ kind: 'drawing', summary: 'drawing', rect: r, strokes: strokeGroup, elements: els.slice(0, 5).map(describe) });
      paint();
    }
  };

  // The keyboard, in pick mode: Tab and arrows walk the page's elements,
  // Enter marks one, Escape stops. Each is said aloud as it is reached.
  const walkable = (el) => {
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0 && !ours(el);
  };
  const focusOn = (el) => {
    if (!el) return;
    focused = el;
    el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    showHover(el);
    live.textContent = name(el);
  };
  const key = (e) => {
    if (!mode) return;
    if (e.key === 'Escape') { post({ type: 'stop' }); return; }
    if (mode !== 'pick') return;
    const all = [...document.body.querySelectorAll('*')].filter(walkable);
    const at = focused ? all.indexOf(focused) : -1;
    let next = null;
    if (e.key === 'Tab') next = all[(at + (e.shiftKey ? -1 : 1) + all.length) % all.length];
    else if (e.key === 'ArrowUp' && focused) next = focused.parentElement !== document.body ? focused.parentElement : null;
    else if (e.key === 'ArrowDown' && focused) next = [...focused.children].find(walkable) || null;
    else if (e.key === 'ArrowRight' && focused) { let s = focused.nextElementSibling; while (s && !walkable(s)) s = s.nextElementSibling; next = s; }
    else if (e.key === 'ArrowLeft' && focused) { let s = focused.previousElementSibling; while (s && !walkable(s)) s = s.previousElementSibling; next = s; }
    else if (e.key === 'Enter' && focused) { e.preventDefault(); pick(focused); return; }
    else return;
    e.preventDefault();
    focusOn(next || all[0]);
  };

  // While marking, a layer over the page takes the mouse, so the page's own
  // links and buttons are not pressed by a mark.
  const setMode = (to) => {
    mode = to;
    if (!host.isConnected) document.documentElement.appendChild(host);
    if (to && !catcher) {
      catcher = document.createElement('div');
      catcher.className = 'catch';
      catcher.addEventListener('mousedown', down);
      catcher.addEventListener('mousemove', move);
      addEventListener('mouseup', up, true);
      root.appendChild(catcher);
    }
    if (!to && catcher) {
      catcher.remove();
      catcher = null;
      hoverBox.hidden = true;
    }
    if (catcher) catcher.style.cursor = to === 'pick' ? 'default' : 'crosshair';
    live.textContent = to === 'pick' ? 'Marking: point at or Tab to an element, Enter to mark it'
      : to === 'region' ? 'Marking: drag over a region' : to === 'draw' ? 'Marking: draw on the page' : '';
  };

  addEventListener('keydown', key, true);
  addEventListener('resize', sizeCanvas);
  // Marks are of where things were: scrolling moves the page under them, so
  // they follow by re-measuring elements, and regions and drawings scroll with it.
  let lastScroll = { x: scrollX, y: scrollY };
  addEventListener('scroll', () => {
    const dx = scrollX - lastScroll.x, dy = scrollY - lastScroll.y;
    lastScroll = { x: scrollX, y: scrollY };
    for (const m of marks) {
      m.rect = { ...m.rect, x: m.rect.x - dx, y: m.rect.y - dy };
      if (m.boxEl) Object.assign(m.boxEl.style, { left: m.rect.x + 'px', top: m.rect.y + 'px' });
      place(m.badgeEl, m.rect.x - 9, m.rect.y - 9);
    }
    for (const s of strokes.flat()) for (const p of s) { p.x -= dx; p.y -= dy; }
    paint();
  }, true);
  sizeCanvas();

  window.__helmyAnnotate = {
    setMode,
    remove: removeMark,
    clear: () => { for (const m of [...marks]) removeMark(m.n); },
    undo: () => marks.length && removeMark(marks[marks.length - 1].n),
    // Whether marks are on the page, for a picture that shows them.
    count: () => marks.length,
    page: () => ({ url: location.href, title: document.title }),
  };
  document.documentElement.appendChild(host);
})();
