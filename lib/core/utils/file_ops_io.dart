// IO implementation of file_ops — dart:io backed.
// API contract is mirrored 1:1 in file_ops_web.dart (selected via conditional
// export in file_ops.dart). Mobile behavior must stay identical to the code
// paths this abstraction replaced.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart' show FileImage, ImageProvider;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// ImageProvider for a local file reference (filesystem path on IO).
ImageProvider localImageProvider(String ref) => FileImage(File(ref));

/// VideoPlayerController for a local file reference.
VideoPlayerController localVideoController(String ref) =>
    VideoPlayerController.file(File(ref));

/// Whether a local file reference still exists.
Future<bool> localRefExists(String ref) async {
  try {
    return File(ref).exists();
  } catch (_) {
    return false;
  }
}

/// Synchronous variant of [localRefExists] for sync build paths.
bool localRefExistsSync(String ref) {
  try {
    return File(ref).existsSync();
  } catch (_) {
    return false;
  }
}

/// Persist document bytes where the user can retrieve them.
/// Returns the absolute path of the written file.
Future<String> saveUserDocument(Uint8List bytes, String fileName) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(bytes);
  return file.path;
}

/// Compress an image to JPEG bytes; falls back to original bytes on failure.
Future<Uint8List> compressImageToBytes(
  XFile file, {
  int quality = 72,
  int maxDimension = 1080,
}) async {
  final tmpDir = await getTemporaryDirectory();
  final outPath =
      '${tmpDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
  final result = await FlutterImageCompress.compressAndGetFile(
    file.path,
    outPath,
    quality: quality,
    minWidth: maxDimension,
    minHeight: maxDimension,
    format: CompressFormat.jpeg,
    keepExif: false,
  );
  if (result == null) return file.readAsBytes();
  return File(result.path).readAsBytes();
}

/// Multipart file for backend upload — path-based (streaming) on IO.
Future<http.MultipartFile> multipartFileFromXFile(String field, XFile file) =>
    http.MultipartFile.fromPath(field, file.path);

/// Best-effort content type derived from a file name extension.
String? contentTypeFor(String fileName) => lookupMimeType(fileName);
