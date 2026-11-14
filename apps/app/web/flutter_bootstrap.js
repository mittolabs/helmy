{{flutter_js}}
{{flutter_build_config}}

// An extension's page registers no service worker of its own: Chrome keeps
// the files, and the extension has its own worker (background.js).
_flutter.loader.load();
