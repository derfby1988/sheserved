// File operations abstraction — conditional export.
// dart.library.js_interop is true only on web (JS/WASM) targets,
// so IO platforms resolve to file_ops_io.dart and web to file_ops_web.dart.
export 'file_ops_io.dart' if (dart.library.js_interop) 'file_ops_web.dart';
