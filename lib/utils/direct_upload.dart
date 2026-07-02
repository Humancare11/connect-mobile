import 'package:file_picker/file_picker.dart';

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
  });

  final String key;
  final String name;
  final String type;
}

Future<UploadCandidate?> pickFileForUpload() async {
  final result = await FilePicker.platform.pickFiles(withData: true);
  final file = result?.files.single;
  if (file == null) return null;

  return UploadCandidate(
    name: file.name,
    sizeBytes: file.size,
    platformFile: file,
  );
}

Future<UploadedFile> uploadFileDirectToS3(UploadCandidate file) async {
  throw UnsupportedError(
    'Direct upload is not configured in this mobile build.',
  );
}
