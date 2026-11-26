import 'dart:typed_data';

import 'package:humancare_connect/services/document_saver.dart';

/// A [DocumentSaver] that touches no phone storage: it records what it was
/// asked to download, save and open.
class FakeDocumentSaver extends DocumentSaver {
  FakeDocumentSaver({
    this.where = SavedWhere.downloads,
    this.failFetch = false,
    this.failSave = false,
    this.outcome = OpenOutcome.opened,
    this.readable = true,
    Uint8List? fetchBytes,
  }) : fetchBytes = fetchBytes ?? Uint8List.fromList('%PDF-1.4 fake'.codeUnits);

  final SavedWhere where;
  final bool failFetch;
  final bool failSave;
  final Uint8List fetchBytes;

  /// What [open] reports, and whether the saved file can still be read.
  final OpenOutcome outcome;
  final bool readable;

  final List<Uri> fetched = [];
  final List<(Uint8List, String)> saved = [];
  final List<String> opened = [];

  @override
  Future<Uint8List> fetch(Uri uri, {client}) async {
    fetched.add(uri);
    if (failFetch) throw Exception('fetch failed');
    return fetchBytes;
  }

  @override
  Future<SavedDocument> save(Uint8List bytes, String filename) async {
    if (failSave) throw Exception('save failed');
    saved.add((bytes, filename));
    return SavedDocument(path: '/cache/documents/$filename', where: where);
  }

  @override
  Future<OpenOutcome> open(String path) async {
    opened.add(path);
    return outcome;
  }

  @override
  Future<Uint8List?> read(String path) async => readable ? fetchBytes : null;
}
