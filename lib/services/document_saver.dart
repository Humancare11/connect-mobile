import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_store_plus/media_store_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../screens/pdf_viewer_screen.dart';

/// Where a downloaded document ended up.
enum SavedWhere {
  /// Android: the public Downloads folder (Downloads/Humancare Connect/).
  downloads,

  /// iOS: the app's Documents folder (visible in the Files app).
  files,

  /// Android fallback: the phone refused a public save (for example Android 10,
  /// or storage permission denied on Android 9 and below). The file is only
  /// opened in a PDF viewer; the user can save it from there.
  viewOnly,
}

/// What happened when the phone was asked to open a saved PDF.
enum OpenOutcome {
  opened,

  /// No app on the phone can open a PDF.
  noApp,

  /// Anything else: the file is gone, access was refused, ...
  failed,
}

class SavedDocument {
  const SavedDocument({required this.path, required this.where});

  /// A path the app itself can open with no storage permission (inside the
  /// app's own folders).
  final String path;
  final SavedWhere where;
}

/// Saves generated or downloaded PDFs on the phone and opens them. Screens take
/// one of these so tests can pass a fake.
class DocumentSaver {
  const DocumentSaver();

  static const String folderName = 'Humancare Connect';
  static const String savedToDownloadsText = 'Saved to Downloads';
  static const String savedToFilesText = 'Saved to Files';
  static const String downloadFailedText =
      'Could not download the PDF. Please try again.';
  static const String openFailedDownloadsText =
      "Couldn't open the file. You can find it in Downloads/$folderName.";
  static const String openFailedFilesText =
      "Couldn't open the file. You can find it in the Files app.";
  static const String openFailedViewOnlyText =
      "Couldn't open the file. Please try downloading again.";

  /// Keeps letters, digits, dot, dash, underscore, space and brackets; anything
  /// else becomes "_". Always ends in ".pdf".
  static String cleanFileName(String name) {
    var cleaned = name.trim();
    if (cleaned.toLowerCase().endsWith('.pdf')) {
      cleaned = cleaned.substring(0, cleaned.length - 4);
    }
    cleaned = cleaned
        .replaceAll(RegExp(r'[^A-Za-z0-9._ ()-]'), '_')
        .replaceAll(RegExp(r'\.{2,}'), '.')
        .replaceAll(RegExp(r'^[. ]+'), '')
        .trim();
    if (cleaned.isEmpty) cleaned = 'document';
    return '$cleaned.pdf';
  }

  /// "name.pdf" -> "name (1).pdf" -> "name (2).pdf" ... until [taken] is false.
  /// Never overwrites, never asks.
  static Future<String> uniqueName(
    String name,
    Future<bool> Function(String candidate) taken,
  ) async {
    if (!await taken(name)) return name;
    final base = name.substring(0, name.length - 4);
    for (var i = 1; i < 1000; i++) {
      final candidate = '$base ($i).pdf';
      if (!await taken(candidate)) return candidate;
    }
    return '$base (${DateTime.now().millisecondsSinceEpoch}).pdf';
  }

  /// Downloads a signed link (no login header, the link carries its own
  /// permission). Throws when the answer is not a normal, non-empty 200.
  Future<Uint8List> fetch(Uri uri, {http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final response = await c.get(uri).timeout(const Duration(seconds: 90));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw const HttpException('download failed');
      }
      return response.bodyBytes;
    } finally {
      if (client == null) c.close();
    }
  }

  Future<SavedDocument> save(Uint8List bytes, String filename) async {
    final wanted = cleanFileName(filename);
    if (Platform.isIOS) return _saveIos(bytes, wanted);
    return _saveAndroid(bytes, wanted);
  }

  Future<SavedDocument> _saveIos(Uint8List bytes, String wanted) async {
    final dir = await getApplicationDocumentsDirectory();
    final name = await uniqueName(
      wanted,
      (candidate) => File('${dir.path}/$candidate').exists(),
    );
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return SavedDocument(path: file.path, where: SavedWhere.files);
  }

  Future<SavedDocument> _saveAndroid(Uint8List bytes, String wanted) async {
    await MediaStore.ensureInitialized();
    MediaStore.appFolder = folderName;
    final store = MediaStore();
    final sdk = await store.getPlatformSDKInt();

    // A copy inside the app's own cache folder. It is what "Open" shows, so no
    // storage permission is needed to open it.
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/documents');
    await dir.create(recursive: true);

    // Android 9 and below write straight into Downloads, which needs the old
    // storage permission (declared with maxSdkVersion 28). Android 10 cannot
    // write there directly without legacy storage, which this app does not use;
    // the package then fails and we fall back to view-only below.
    final canSaveToDownloads = sdk <= 28
        ? (await Permission.storage.request()).isGranted
        : true;

    String name = wanted;
    if (canSaveToDownloads) {
      try {
        name = await uniqueName(
          wanted,
          (candidate) => store.isFileExist(
            fileName: candidate,
            dirType: DirType.download,
            dirName: DirName.download,
          ),
        );
      } catch (_) {
        name = wanted;
      }
    }
    final tmpFile = File('${dir.path}/$name');
    await tmpFile.writeAsBytes(bytes, flush: true);

    if (canSaveToDownloads) {
      try {
        final info = await publishCopy(
          tmpFile,
          (path) => store.saveFile(
            tempFilePath: path,
            dirType: DirType.download,
            dirName: DirName.download,
          ),
        );
        if (info != null) {
          return SavedDocument(path: tmpFile.path, where: SavedWhere.downloads);
        }
      } catch (_) {
        // Fall through to view-only.
      }
    }
    return SavedDocument(path: tmpFile.path, where: SavedWhere.viewOnly);
  }

  /// Hands [publish] a throwaway copy of [keep], with the same file name.
  ///
  /// media_store_plus deletes the file it is given once it has copied it to
  /// Downloads (Android 11 and newer). Without this, the file "Open" needs
  /// would be gone.
  @visibleForTesting
  static Future<T> publishCopy<T>(
    File keep,
    Future<T> Function(String path) publish,
  ) async {
    final dir = Directory('${keep.parent.path}/upload');
    await dir.create(recursive: true);
    final copy = await keep.copy('${dir.path}/${keep.uri.pathSegments.last}');
    try {
      return await publish(copy.path);
    } finally {
      try {
        if (await copy.exists()) await copy.delete();
      } catch (_) {
        // It sits in the cache folder; the phone clears it.
      }
    }
  }

  /// Asks the phone to open the PDF in another app.
  Future<OpenOutcome> open(String path) async {
    try {
      final result = await OpenFilex.open(path, type: 'application/pdf');
      // The type only: the file name carries the patient's name.
      debugPrint('open_filex: ${result.type}');
      return outcomeOf(result.type);
    } catch (error) {
      debugPrint('open_filex failed: ${error.runtimeType}');
      return OpenOutcome.failed;
    }
  }

  @visibleForTesting
  static OpenOutcome outcomeOf(ResultType type) => switch (type) {
    ResultType.done => OpenOutcome.opened,
    ResultType.noAppToOpen => OpenOutcome.noApp,
    _ => OpenOutcome.failed,
  };

  /// The saved file's content for the in-app viewer, or null when it cannot be
  /// read.
  Future<Uint8List?> read(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }
}

/// "Open": another app if the phone has one, otherwise the app's own viewer,
/// otherwise a message saying where the file is.
Future<void> openSaved(
  ScaffoldMessengerState messenger,
  DocumentSaver saver,
  SavedDocument saved, {
  NavigatorState? navigator,
}) async {
  if (await saver.open(saved.path) == OpenOutcome.opened) return;

  final failedText = switch (saved.where) {
    SavedWhere.downloads => DocumentSaver.openFailedDownloadsText,
    SavedWhere.files => DocumentSaver.openFailedFilesText,
    SavedWhere.viewOnly => DocumentSaver.openFailedViewOnlyText,
  };

  final bytes = await saver.read(saved.path);
  if (bytes != null && navigator != null && navigator.mounted) {
    // Not awaited: it completes only when the viewer is closed.
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => PdfViewerScreen(
            title: saved.path.split(RegExp(r'[/\\]')).last,
            bytes: bytes,
            errorText: failedText,
          ),
        ),
      ),
    );
    return;
  }
  if (messenger.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(failedText)));
  }
}

/// Shows the result of a save: the snackbar ("Saved to Downloads" with one
/// "Open" action), or on iOS "Saved to Files" and the preview straight away.
/// When the phone refused a public save the PDF just opens in the viewer.
Future<void> announceSaved(
  ScaffoldMessengerState messenger,
  DocumentSaver saver,
  SavedDocument saved, {
  NavigatorState? navigator,
}) async {
  Future<void> openIt() =>
      openSaved(messenger, saver, saved, navigator: navigator);

  switch (saved.where) {
    case SavedWhere.downloads:
      messenger.showSnackBar(
        SnackBar(
          content: const Text(DocumentSaver.savedToDownloadsText),
          action: SnackBarAction(
            label: 'Open',
            onPressed: openIt,
          ),
        ),
      );
    case SavedWhere.files:
      messenger.showSnackBar(
        const SnackBar(content: Text(DocumentSaver.savedToFilesText)),
      );
      await openIt();
    case SavedWhere.viewOnly:
      await openIt();
  }
}
