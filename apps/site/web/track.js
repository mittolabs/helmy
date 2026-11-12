// What Umami cannot count from a click alone, on helmy.ke and its docs: an install
// command copied, and a tutorial played (once per page view). Nothing when Umami is
// not loaded (Do Not Track, development).
(() => {
  const send = (name, data) => window.umami && window.umami.track(name, data);
  document.addEventListener('copy', () => {
    const cmd = document.getSelection()?.anchorNode?.parentElement?.closest('.download-cmd');
    if (cmd) send('install-command', { system: cmd.dataset.system || '' });
  });
  for (const v of document.querySelectorAll('video')) {
    const name = (v.getAttribute('src') || '').split('/').pop().replace(/\.mp4$/, '');
    v.addEventListener('play', () => send('tutorial-play', { video: name }), { once: true });
    v.addEventListener('ended', () => send('tutorial-finished', { video: name }), { once: true });
  }
})();
