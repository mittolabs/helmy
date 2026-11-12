// How many stars Helmy has on GitHub, into every [data-stars]: read from GitHub's API and
// shown only when there are some. A count is kept five minutes in the browser; none is
// kept, so a first star shows on the next visit, and clicking Star forgets the count, so
// coming back after starring reads it again.
(() => {
  const els = document.querySelectorAll('[data-stars]');
  if (!els.length) return;
  const key = 'helmy-stars';
  const forget = () => { try { localStorage.removeItem(key); } catch {} };
  for (const a of document.querySelectorAll('a.star')) a.addEventListener('click', forget);
  const show = n => {
    if (!(n > 0)) return;
    const text = n >= 1000 ? `${(n / 1000).toFixed(n >= 10000 ? 0 : 1).replace(/\.0$/, '')}k` : String(n);
    for (const el of els) { el.textContent = text; el.closest('.star')?.classList.add('has-count'); }
  };
  try {
    const kept = JSON.parse(localStorage.getItem(key) || 'null');
    if (kept && kept.n > 0 && Date.now() - kept.at < 300_000) return show(kept.n);
  } catch {}
  fetch('https://api.github.com/repos/mittolabs/helmy', { headers: { Accept: 'application/vnd.github+json' } })
    .then(r => (r.ok ? r.json() : null))
    .then(j => {
      if (!j || typeof j.stargazers_count !== 'number') return;
      if (j.stargazers_count > 0) {
        try { localStorage.setItem(key, JSON.stringify({ n: j.stargazers_count, at: Date.now() })); } catch {}
      }
      show(j.stargazers_count);
    })
    .catch(() => {});
})();
