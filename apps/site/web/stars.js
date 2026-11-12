// How many stars Helmy has on GitHub, into every [data-stars]: read from GitHub's API,
// kept for an hour in the browser, and shown only when there are some.
(() => {
  const els = document.querySelectorAll('[data-stars]');
  if (!els.length) return;
  const show = n => {
    if (!(n > 0)) return;
    const text = n >= 1000 ? `${(n / 1000).toFixed(n >= 10000 ? 0 : 1).replace(/\.0$/, '')}k` : String(n);
    for (const el of els) { el.textContent = text; el.closest('.star')?.classList.add('has-count'); }
  };
  const key = 'helmy-stars';
  try {
    const kept = JSON.parse(localStorage.getItem(key) || 'null');
    if (kept && Date.now() - kept.at < 3600_000) return show(kept.n);
  } catch {}
  fetch('https://api.github.com/repos/mittolabs/helmy', { headers: { Accept: 'application/vnd.github+json' } })
    .then(r => (r.ok ? r.json() : null))
    .then(j => {
      if (!j || typeof j.stargazers_count !== 'number') return;
      try { localStorage.setItem(key, JSON.stringify({ n: j.stargazers_count, at: Date.now() })); } catch {}
      show(j.stargazers_count);
    })
    .catch(() => {});
})();
