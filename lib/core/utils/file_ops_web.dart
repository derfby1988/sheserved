// Web implementation of file_ops — dart:io is unavailable here, so a "local
// file reference" is a blob: URL (XFile.path from pickers is already one).
// API contract is mirrored 1:1 in file_ops_io.dart.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/painting.dart' show ImageProvider, NetworkImage;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

/// ImageProvider for a local file reference (blob: URL on web).
ImageProvider localImageProvider(String ref) => NetworkImage(ref);

/// VideoPlayerController for a local file reference — blob: URLs are playable
/// through the network controller on web.
VideoPlayerController localVideoController(String ref) =>
    VideoPlayerController.networkUrl(Uri.parse(ref));

/// Blob references are session-scoped and always "exist" while alive.
Future<bool> localRefExists(String ref) async => localRefExistsSync(ref);

/// Synchronous variant of [localRefExists] for sync build paths.
bool localRefExistsSync(String ref) => ref.startsWith('blob:');

/// Persist document bytes by triggering a browser download.
/// Returns the download file name.
Future<String> saveUserDocument(Uint8List bytes, String fileName) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(
      type: contentTypeFor(fileName) ?? 'application/octet-stream',
    ),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor =
      web.document.createElement('a') as web.HTMLAnchorElement
        ..href = url
        ..download = fileName;
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return fileName;
}

/// flutter_image_compress has no web implementation — return original bytes.
Future<Uint8List> compressImageToBytes(
  XFile file, {
  int quality = 72,
  int maxDimension = 1080,
}) =>
    file.readAsBytes();

/// Multipart file for backend upload — bytes-based on web (no filesystem).
/// Filename + content type are attached so the server does not see a bare
/// application/octet-stream blob.
Future<http.MultipartFile> multipartFileFromXFile(
  String field,
  XFile file,
) async {
  final mime = contentTypeFor(file.name);
  return http.MultipartFile.fromBytes(
    field,
    await file.readAsBytes(),
    filename: file.name,
    contentType: mime == null ? null : MediaType.parse(mime),
  );
}

/// Best-effort content type derived from a file name extension.
String? contentTypeFor(String fileName) => lookupMimeType(fileName);
