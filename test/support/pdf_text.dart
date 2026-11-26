import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The words of a PDF made by the `pdf` package, in drawing order and joined by
/// single spaces. Only enough of the format for those files: embedded TrueType
/// fonts with a ToUnicode map and deflated streams.
String pdfText(Uint8List bytes) {
  final source = latin1.decode(bytes);
  final dictionaries = <int, String>{};
  final streams = <int, String>{};

  for (final match in RegExp(
    r'(\d+) 0 obj(.*?)endobj',
    dotAll: true,
  ).allMatches(source)) {
    final id = int.parse(match[1]!);
    final body = match[2]!;
    final start = body.indexOf('stream');
    if (start < 0) {
      dictionaries[id] = body;
      continue;
    }
    final dictionary = body.substring(0, start);
    dictionaries[id] = dictionary;
    var data = start + 'stream'.length;
    while (body[data] == '\r' || body[data] == '\n') {
      data++;
    }
    final length = int.parse(
      RegExp(r'/Length (\d+)').firstMatch(dictionary)![1]!,
    );
    final raw = latin1.encode(body.substring(data, data + length));
    if (dictionary.contains('/Subtype/Image')) continue;
    streams[id] = latin1.decode(
      dictionary.contains('/FlateDecode') ? zlib.decode(raw) : raw,
    );
  }

  // Font resource name (/F5) -> glyph code -> character.
  final fonts = <String, Map<int, int>>{};
  for (final entry in dictionaries.entries) {
    final unicode = RegExp(r'/ToUnicode (\d+) 0 R').firstMatch(entry.value);
    final name = RegExp(r'/Name\s*(/F\d+)').firstMatch(entry.value);
    if (unicode == null || name == null) continue;
    final map = <int, int>{};
    final cmap = streams[int.parse(unicode[1]!)] ?? '';
    for (final block in RegExp(
      r'beginbfchar(.*?)endbfchar',
      dotAll: true,
    ).allMatches(cmap)) {
      for (final pair in RegExp(
        r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
      ).allMatches(block[1]!)) {
        map[int.parse(pair[1]!, radix: 16)] = int.parse(pair[2]!, radix: 16);
      }
    }
    fonts[name[1]!] = map;
  }

  final words = <String>[];
  for (final stream in streams.values) {
    if (!stream.contains(' Tf')) continue;
    var font = const <int, int>{};
    for (final token in RegExp(
      r'(/F\d+) [\d.]+ Tf|<([0-9A-Fa-f]*)>',
    ).allMatches(stream)) {
      if (token[1] != null) {
        font = fonts[token[1]!] ?? const {};
        continue;
      }
      final hex = token[2]!;
      words.add(
        String.fromCharCodes([
          for (var i = 0; i + 4 <= hex.length; i += 4)
            font[int.parse(hex.substring(i, i + 4), radix: 16)] ?? 0xFFFD,
        ]),
      );
    }
  }
  return words.join(' ').replaceAll(RegExp(r'\s+'), ' ');
}
