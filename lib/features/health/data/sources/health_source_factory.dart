// Health source factory — conditional export.
// Keeps package:health (and its dart:io/platform-channel graph) out of the
// web bundle; web resolves to a factory returning null.
export 'health_source_factory_io.dart'
    if (dart.library.js_interop) 'health_source_factory_web.dart';
