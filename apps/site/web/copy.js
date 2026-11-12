// The copy buttons beside the install commands: the command to the clipboard, a check for
// a moment, and counted (track.js's Umami) when it is on.
(() => {
  for (const b of document.querySelectorAll('button.copy[data-copy]')) {
    b.addEventListener('click', async () => {
      try { await navigator.clipboard.writeText(b.dataset.copy); } catch { return; }
      b.classList.add('done');
      setTimeout(() => b.classList.remove('done'), 1600);
      const system = b.closest('.download-cmd')?.dataset.system || '';
      window.umami && window.umami.track('install-command', { system });
    });
  }
})();
