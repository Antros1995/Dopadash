{{flutter_js}}
{{flutter_build_config}}

// Local desktop builds must always load the current bundle. A service worker
// would keep an older dashboard alive even when build/web has been replaced.
_flutter.loader.load();
