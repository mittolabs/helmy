// "This page": run in the tab by the side panel when asked, and only then.
// Its value is what the panel sends: where the page is, its title, what is
// selected on it and its readable text, trimmed.
(() => {
  const tidy = (s, max) =>
    String(s || '').replace(/[ \t]+\n/g, '\n').replace(/\n{3,}/g, '\n\n').trim().slice(0, max);
  const main =
    document.querySelector('main, article, [role="main"]') || document.body || document.documentElement;
  return {
    url: location.href,
    title: document.title,
    selection: tidy(getSelection(), 20000),
    text: tidy(main && main.innerText, 100000),
  };
})();
