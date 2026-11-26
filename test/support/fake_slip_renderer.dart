import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:humancare_connect/widgets/slips/slip_pdf_view.dart';

/// Stands in for the phone's PDF engine: remembers what it was asked to draw
/// and answers with blank A4-shaped pages.
class FakeSlipRenderer {
  FakeSlipRenderer._(this._page);

  final ui.Image _page;
  final List<Future<Uint8List> Function()> builds = [];
  int pageCount = 1;
  bool fail = false;

  /// Installs itself for the current test.
  static Future<FakeSlipRenderer> install(WidgetTester tester) async {
    final page = (await tester.runAsync(
      () => createTestImage(width: 210, height: 297),
    ))!;
    final fake = FakeSlipRenderer._(page);
    SlipPdfView.renderPages = (buildPdf, widthPx) async {
      fake.builds.add(buildPdf);
      if (fake.fail) throw StateError('cannot draw');
      return [for (var i = 0; i < fake.pageCount; i++) page.clone()];
    };
    addTearDown(() {
      SlipPdfView.renderPages = SlipPdfView.renderWithPhone;
      fake._page.dispose();
    });
    return fake;
  }

  /// Builds the PDF the screen asked to have drawn.
  Future<Uint8List> lastPdf(WidgetTester tester) async =>
      (await tester.runAsync(builds.last))!;
}
