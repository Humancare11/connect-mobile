import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../services/api_service.dart';
import '../services/token_storage_service.dart';

class UploadCandidate {
  const UploadCandidate({
    required this.name,
    required this.sizeBytes,
    required this.platformFile,
  });

  final String name;
  final int sizeBytes;
  final PlatformFile platformFile;
}

class UploadedFile {
  const UploadedFile({
    required this.key,
    required this.name,
    required this.type,
    required this.sizeBytes,
  });

  final String key;
  final String name;
  final String type;
  final int sizeBytes;
}

const int _maxUploadBytes = 10 * 1024 * 1024;

// Mirrors the web version's <input accept="..."> for the appointment booking
// upload zone — intentionally narrower than the backend's full ALLOWED_TYPES
// (which also accepts .txt) so the picker offers the same file set as web.
const List<String> bookingUploadExtensions = [
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'jpg', 'jpeg', 'png', 'gif', 'webp',
];

// Mirrors backend/routes/upload.js's ALLOWED_TYPES — the presign endpoint
// rejects any contentType that isn't exactly one of these values for the
// given extension, so this must stay a strict match, not a best-effort guess.
const Map<String, String> _extensionContentTypes = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.gif': 'image/gif',
  '.webp': 'image/webp',
  '.pdf': 'application/pdf',
  '.txt': 'text/plain',
  '.doc': 'application/msword',
  '.xls': 'application/vnd.ms-excel',
  '.docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

String _guessContentType(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0) return 'application/octet-stream';
  final ext = fileName.substring(dot).toLowerCase();
  return _extensionContentTypes[ext] ?? 'application/octet-stream';
}

final TokenStorageService _tokenStorage = const TokenStorageService();

Future<UploadCandidate?> pickFileForUpload() async {
  final result = await FilePicker.platform.pickFiles(withData: kIsWeb);
  final file = result?.files.single;
  if (file == null) return null;

  return UploadCandidate(
    name: file.name,
    sizeBytes: file.size,
    platformFile: file,
  );
}

/// Multi-select variant used by the appointment booking upload zone, mirroring
/// the web version's `<input type="file" multiple accept="...">`.
Future<List<UploadCandidate>> pickFilesForUpload() async {
  final result = await FilePicker.platform.pickFiles(
    // Mobile streams from the file path; only web has no path to read.
    withData: kIsWeb,
    allowMultiple: true,
    type: FileType.custom,
    allowedExtensions: bookingUploadExtensions,
  );
  final files = result?.files ?? const <PlatformFile>[];

  return files
      .map(
        (file) => UploadCandidate(
          name: file.name,
          sizeBytes: file.size,
          platformFile: file,
        ),
      )
      .toList();
}

/// Ported from frontend/src/utils/directUpload.js's uploadFileDirectToS3:
/// presign -> PUT direct to S3 -> multipart POST /api/upload fallback if the
/// PUT fails. The presign call itself is deliberately left unguarded (same as
/// the web version) — only the S3 PUT is allowed to fall back.
Future<UploadedFile> uploadFileDirectToS3(UploadCandidate file) async {
  if (file.sizeBytes > _maxUploadBytes) {
    throw Exception(
      '"${file.name}" is larger than 10 MB. Please choose a smaller file.',
    );
  }

  final path = kIsWeb ? null : file.platformFile.path;
  final bytes = file.platformFile.bytes;
  if (path == null && bytes == null) {
    throw Exception('Could not read the selected file.');
  }

  final contentType = _guessContentType(file.name);

  final presign =
      await ApiService.instance.post('/api/upload/presign', {
            'originalName': file.name,
            'contentType': contentType,
            'size': file.sizeBytes,
          })
          as Map<String, dynamic>;

  final uploadUrl = presign['uploadUrl']?.toString();
  if (uploadUrl == null || uploadUrl.isEmpty) {
    throw Exception('Server did not return an upload URL.');
  }

  try {
    final headers = <String, String>{'Content-Type': contentType};
    final presignedHeaders = presign['headers'];
    if (presignedHeaders is Map) {
      presignedHeaders.forEach((key, value) {
        headers[key.toString()] = value.toString();
      });
    }

    final http.Response putResponse;
    if (path != null) {
      // Stream from disk so the whole file is never held in memory.
      final putRequest = http.StreamedRequest('PUT', Uri.parse(uploadUrl))
        ..headers.addAll(headers)
        ..contentLength = file.sizeBytes;
      File(path).openRead().listen(
        putRequest.sink.add,
        onError: putRequest.sink.addError,
        onDone: putRequest.sink.close,
        cancelOnError: true,
      );
      putResponse = await http.Response.fromStream(
        await putRequest.send().timeout(const Duration(seconds: 60)),
      );
    } else {
      putResponse = await http
          .put(Uri.parse(uploadUrl), headers: headers, body: bytes)
          .timeout(const Duration(seconds: 60));
    }

    if (putResponse.statusCode < 200 || putResponse.statusCode >= 300) {
      throw Exception('Upload to S3 failed.');
    }

    final fileInfo = presign['file'];
    if (fileInfo is Map) {
      return UploadedFile(
        key: (fileInfo['key'] ?? fileInfo['url'] ?? uploadUrl).toString(),
        name: (fileInfo['name'] ?? file.name).toString(),
        type: (fileInfo['type'] ?? contentType).toString(),
        sizeBytes: (fileInfo['size'] as num?)?.toInt() ?? file.sizeBytes,
      );
    }
    return UploadedFile(
      key: uploadUrl,
      name: file.name,
      type: contentType,
      sizeBytes: file.sizeBytes,
    );
  } catch (_) {
    return _uploadViaMultipartFallback(file, path, bytes, contentType);
  }
}

Future<UploadedFile> _uploadViaMultipartFallback(
  UploadCandidate file,
  String? path,
  Uint8List? bytes,
  String contentType,
) async {
  final token = await _tokenStorage.getToken() ?? '';
  final uri = Uri.parse('${ApiConfig.baseUrl}/upload');

  final request = http.MultipartRequest('POST', uri)
    ..headers.addAll({
      'Accept': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    })
    ..files.add(
      path != null
          ? await http.MultipartFile.fromPath('file', path, filename: file.name)
          : http.MultipartFile.fromBytes('file', bytes!, filename: file.name),
    );

  final streamedResponse = await request.send().timeout(
    const Duration(seconds: 60),
  );
  final response = await http.Response.fromStream(streamedResponse);

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(_extractErrorMessage(response.body) ?? 'File upload failed.');
  }

  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  return UploadedFile(
    key: (decoded['key'] ?? decoded['url'] ?? '').toString(),
    name: (decoded['name'] ?? file.name).toString(),
    type: (decoded['type'] ?? contentType).toString(),
    sizeBytes: (decoded['size'] as num?)?.toInt() ?? file.sizeBytes,
  );
}

String? _extractErrorMessage(String body) {
  if (body.isEmpty) return null;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['msg'] is String) {
      return decoded['msg'] as String;
    }
  } catch (_) {
    // Non-JSON error body — fall through to the generic message.
  }
  return null;
}
