import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../utils/file_ops.dart';
import 'authenticated_http_client.dart';

/// W2 decision (b): server-side PDPA face blur for clients without
/// on-device ML Kit (Flutter Web). Uses the backend's existing
/// deface/CenterFace pipeline via `POST /api/media/face-blur`.
///
/// Fail-closed: throws on any failure — callers must NOT fall back to
/// uploading the unblurred image. Requires backend auth (Bearer) or the
/// compat `x-user-id` window; in direct-Supabase dev mode without a
/// configured backend this will throw and the upload is blocked.
Future<Uint8List> blurImageViaBackend({
  required Uint8List bytes,
  required String filename,
  String? userId,
}) async {
  final mimeType = contentTypeFor(filename);
  final response = await AuthenticatedHttpClient.instance.sendMultipart(
    () async {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          '${AuthenticatedHttpClient.instance.backendApiUrl}/api/media/face-blur',
        ),
      );
      // Compat window: server prefers Bearer; x-user-id keeps direct mode
      // working (same convention as video_repository uploads).
      if (userId != null) request.headers['x-user-id'] = userId;
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes,
          filename: filename,
          contentType: mimeType != null ? MediaType.parse(mimeType) : null,
        ),
      );
      return request;
    },
  );

  if (response.statusCode != 200) {
    throw StateError('Face blur unavailable: HTTP ${response.statusCode}');
  }
  return response.stream.toBytes();
}
