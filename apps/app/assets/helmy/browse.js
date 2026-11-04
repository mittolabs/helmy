// Helmy's page reader and driver for agents, injected into the page in the
// Preview panel (the built-in browser and Chromium alike). It reads the page
// as a compact outline (headings, text, and everything that can be used,
// each with a short ref such as e12) so an agent works from text, not
// screenshots; and it acts on those refs.
(() => {
  if (window.__helmyBrowse) return;

  // Errors the page reports, for browser_logs.
  const logs = [];
  const keep = (kind, text) => {
    logs.push(`${kind}: ${String(text).slice(0, 500)}`);
    if (logs.length > 100) logs.shift();
  };
  for (const level of ['error', 'warn']) {
    const was = console[level];
    console[level] = (...args) => {
      keep(level, args.map((a) => (a && a.stack) || (typeof a === 'object' ? safeJson(a) : a)).join(' '));
      return was.apply(console, args);
    };
  }
  addEventListener('error', (e) => keep('error', e.message || e), true);
  addEventListener('unhandledrejection', (e) => keep('unhandled', (e.reason && e.reason.stack) || e.reason));
  function safeJson(v) { try { return JSON.stringify(v); } catch (_) { return String(v); } }

  let next = 1;
  const refOf = (el) => {
    if (!el.dataset.helmyRef) el.dataset.helmyRef = 'e' + next++;
    return el.dataset.helmyRef;
  };
  const byRef = (ref) => document.querySelector(`[data-helmy-ref="${ref}"]`);

  const hidden = (el) => {
    if (el.closest('[data-helmy-annotate]')) return true;
    if (el.getAttribute('aria-hidden') === 'true') return true;
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden' || cs.opacity === '0') return true;
    const r = el.getBoundingClientRect();
    return r.width === 0 && r.height === 0 && cs.position !== 'fixed';
  };

  const ROLES = ['button', 'link', 'checkbox', 'radio', 'tab', 'menuitem', 'option', 'switch',
    'combobox', 'textbox', 'searchbox', 'slider', 'spinbutton', 'treeitem'];
  const usable = (el) => {
    const tag = el.tagName;
    if (tag === 'A' && el.hasAttribute('href')) return true;
    if (['BUTTON', 'SELECT', 'TEXTAREA', 'SUMMARY'].includes(tag)) return true;
    if (tag === 'INPUT') return el.type !== 'hidden';
    if (el.isContentEditable && el.getAttribute('contenteditable') !== null) return true;
    const role = el.getAttribute('role');
    if (role && ROLES.includes(role)) return true;
    return el.hasAttribute('onclick') || el.tabIndex >= 0 && el.hasAttribute('tabindex');
  };

  const clean = (s, max = 120) => (s || '').replace(/\s+/g, ' ').trim().slice(0, max);
  const nameOf = (el) => {
    const by = el.getAttribute('aria-labelledby');
    if (by) {
      const t = by.split(/\s+/).map((id) => document.getElementById(id)).filter(Boolean).map((n) => n.innerText).join(' ');
      if (clean(t)) return clean(t);
    }
    const label = el.getAttribute('aria-label') || (el.id && document.querySelector(`label[for="${CSS.escape(el.id)}"]`)?.innerText)
      || el.closest('label')?.innerText || el.getAttribute('placeholder') || el.getAttribute('title') || el.getAttribute('alt');
    if (clean(label)) return clean(label);
    if (el.tagName === 'INPUT' && ['submit', 'button', 'reset'].includes(el.type)) return clean(el.value);
    return clean(el.innerText || el.textContent);
  };
  const kindOf = (el) => {
    const role = el.getAttribute('role');
    if (role) return role;
    switch (el.tagName) {
      case 'A': return 'link';
      case 'BUTTON': case 'SUMMARY': return 'button';
      case 'SELECT': return 'select';
      case 'TEXTAREA': return 'textbox';
      case 'INPUT':
        if (['checkbox', 'radio'].includes(el.type)) return el.type;
        if (['submit', 'button', 'reset', 'image'].includes(el.type)) return 'button';
        if (el.type === 'search') return 'searchbox';
        return el.type === 'text' ? 'textbox' : `${el.type} field`;
    }
    return el.isContentEditable ? 'textbox' : 'clickable';
  };

  const lineFor = (el) => {
    const kind = kindOf(el);
    let line = `${kind} "${nameOf(el)}" [${refOf(el)}]`;
    if (kind === 'link') {
      const href = el.getAttribute('href') || '';
      if (href && !href.startsWith('javascript:')) {
        try {
          const u = new URL(href, location.href);
          line += ' → ' + (u.origin === location.origin ? u.pathname + u.search + u.hash : u.href);
        } catch (_) { /* a malformed link keeps no address */ }
      }
    }
    if (['checkbox', 'radio', 'switch'].includes(kind)) line += el.checked || el.getAttribute('aria-checked') === 'true' ? ' checked' : ' unchecked';
    if (el.tagName === 'SELECT') line += ` = "${clean(el.options[el.selectedIndex]?.text)}"`;
    else if ('value' in el && el.tagName !== 'BUTTON' && el.type !== 'submit' && !['checkbox', 'radio'].includes(el.type)) {
      line += el.type === 'password' ? (el.value ? ' (filled)' : ' (empty)') : ` = "${clean(el.value, 80)}"`;
    }
    if (el.disabled || el.getAttribute('aria-disabled') === 'true') line += ' disabled';
    if (document.activeElement === el) line += ' focused';
    return line;
  };

  // The page as an outline: headings, text, and what can be used.
  const snapshot = (max = 12000) => {
    const lines = [];
    let size = 0, more = 0;
    const add = (line) => {
      if (size + line.length > max) { more++; return; }
      lines.push(line);
      size += line.length + 1;
    };
    const walk = (node) => {
      for (const child of node.childNodes) {
        if (child.nodeType === 3) {
          const t = clean(child.textContent, 300);
          if (t.length > 1) add(t);
          continue;
        }
        if (child.nodeType !== 1) continue;
        const el = child;
        if (['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'SVG', 'svg'].includes(el.tagName)) {
          if (el.tagName.toLowerCase() === 'svg' && usable(el)) add(lineFor(el));
          continue;
        }
        if (hidden(el)) continue;
        if (/^H[1-6]$/.test(el.tagName)) { add('#'.repeat(+el.tagName[1]) + ' ' + clean(el.innerText, 200)); continue; }
        if (el.tagName === 'IMG') { const alt = clean(el.alt); if (alt) add(`image "${alt}"`); continue; }
        if (usable(el)) {
          add(lineFor(el));
          // A select's or a button's own text is said in its line.
          if (['SELECT', 'BUTTON', 'A', 'TEXTAREA', 'INPUT'].includes(el.tagName)) continue;
        }
        if (el.shadowRoot) walk(el.shadowRoot);
        walk(el);
      }
    };
    walk(document.body);
    // Text runs of a few words, one per line, merged for reading.
    const merged = [];
    for (const l of lines) {
      const plain = !/\[e\d+\]/.test(l) && !l.startsWith('#') && !l.startsWith('image "');
      const last = merged[merged.length - 1];
      if (plain && last !== undefined && last.plain && (last.text.length + l.length) < 300) last.text += ' ' + l;
      else merged.push({ text: l, plain });
    }
    let text = merged.map((m) => m.text).join('\n');
    if (more) text += `\n… ${more} more lines; browser_read with find narrows it down.`;
    return { url: location.href, title: document.title, text };
  };

  // Refs whose name, kind or text holds [query]; or a CSS selector's matches.
  const find = (query) => {
    const q = query.trim();
    let els;
    if (q.startsWith('css:')) {
      try { els = [...document.querySelectorAll(q.slice(4))]; } catch (e) { return { error: 'Not a selector: ' + e.message }; }
    } else {
      const lower = q.toLowerCase();
      els = [...document.querySelectorAll('body *')].filter((el) => !hidden(el) && usable(el)
        && (nameOf(el) + ' ' + kindOf(el)).toLowerCase().includes(lower));
      if (!els.length) {
        // Text that is not a control: the elements that say it.
        els = [...document.querySelectorAll('body *')].filter((el) => !hidden(el)
          && [...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.toLowerCase().includes(lower)));
      }
    }
    return { matches: els.slice(0, 30).map((el) => (usable(el) ? lineFor(el) : `${el.tagName.toLowerCase()} "${clean(el.innerText, 160)}" [${refOf(el)}]`)) };
  };

  // Where a ref is on screen, brought into view first, for a real click.
  const point = (ref) => {
    const el = byRef(ref);
    if (!el) return { error: `No element ${ref} on the page now; read it again for new refs.` };
    el.scrollIntoView({ block: 'center', inline: 'center' });
    const r = el.getBoundingClientRect();
    return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  };

  // Actions done in the page itself, where the engine has no real input.
  const setValue = (el, value) => {
    const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
    if (setter && 'value' in el) setter.call(el, value); else el.textContent = value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  };
  const act = (step) => {
    const el = step.ref ? byRef(step.ref) : document.activeElement;
    if (step.ref && !el) return { error: `No element ${step.ref} on the page now; read it again for new refs.` };
    switch (step.do) {
      case 'click':
        el.scrollIntoView({ block: 'center' });
        el.focus?.();
        el.click();
        return { ok: true };
      case 'type':
        el.focus?.();
        setValue(el, step.replace === false ? (el.value || '') + step.text : step.text);
        return { ok: true };
      case 'select': {
        const opt = [...el.options].find((o) => o.value === step.value || clean(o.text) === step.value);
        if (!opt) return { error: `No option "${step.value}" in ${step.ref}.` };
        el.value = opt.value;
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return { ok: true };
      }
      case 'press': {
        const target = el || document.body;
        for (const type of ['keydown', 'keyup']) target.dispatchEvent(new KeyboardEvent(type, { key: step.key, bubbles: true }));
        if (step.key === 'Enter' && target.form) target.form.requestSubmit ? target.form.requestSubmit() : target.form.submit();
        return { ok: true };
      }
      case 'scroll':
        if (el && step.ref) el.scrollIntoView({ block: 'center' });
        else scrollBy(0, (step.by || 0.8) * innerHeight);
        return { ok: true };
    }
    return { error: `Unknown action ${step.do}.` };
  };

  // Settled: loaded, and the page has stopped changing for a moment.
  const settled = (quietMs = 300) => new Promise((done) => {
    let timer;
    const end = () => { observer.disconnect(); done(true); };
    const observer = new MutationObserver(() => { clearTimeout(timer); timer = setTimeout(end, quietMs); });
    const start = () => {
      observer.observe(document.documentElement, { subtree: true, childList: true, attributes: true, characterData: true });
      timer = setTimeout(end, quietMs);
    };
    if (document.readyState === 'complete') start(); else addEventListener('load', start, { once: true });
    setTimeout(() => { observer.disconnect(); done(false); }, 6000);
  });

  window.__helmyBrowse = { snapshot, find, point, act, settled, logs: () => logs.slice() };
})();
