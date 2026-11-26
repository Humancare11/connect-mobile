import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humancare_connect/widgets/slips/slip_pdf_view.dart';

import 'support/fake_slip_renderer.dart';

final _firstPage = find.byKey(const ValueKey('slip page 1'));

/// The slip inside a scrolling list, as both screens have it.
Future<ScrollController> _pump(
  WidgetTester tester, {
  double screen = 360,
  String version = 'a',
  ScrollController? controller,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(screen, 640);
  addTearDown(tester.view.reset);
  final scroll = controller ?? ScrollController();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(
          controller: scroll,
          children: [
            SlipPdfView(
              buildPdf: () => throw StateError('not built in this test'),
              version: version,
              label: 'Prescription',
            ),
            const SizedBox(height: 900),
          ],
        ),
      ),
    ),
  );
  return scroll;
}

TransformationController _zoom(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
    .transformationController!;

double _scale(WidgetTester tester) => _zoom(tester).value.getMaxScaleOnAxis();

Future<void> _doubleTap(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(at);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a spinner until the pages are drawn', (tester) async {
    await FakeSlipRenderer.install(tester);
    await _pump(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(_firstPage, findsOneWidget);
  });

  for (final screen in [320.0, 360.0, 412.0]) {
    testWidgets(
      'each page fits a ${screen.toInt()} phone, stacked, with no sideways '
      'scroll, whatever the text size',
      (tester) async {
        final renderer = await FakeSlipRenderer.install(tester);
        renderer.pageCount = 2;
        await _pump(tester, screen: screen, textScale: 1.6);
        await tester.pumpAndSettle();

        final first = tester.getRect(_firstPage);
        expect(first.left, 8);
        expect(first.width, screen - 16);
        expect(first.height, closeTo(first.width * 297 / 210, 0.5));
        final second = tester.getRect(
          find.byKey(const ValueKey('slip page 2')),
        );
        expect(second.top, closeTo(first.bottom + 8, 0.5));
        expect(
          tester
              .widgetList<Scrollable>(find.byType(Scrollable))
              .where((s) => s.axisDirection == AxisDirection.right),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a failure shows the message, and Retry draws again', (
    tester,
  ) async {
    final renderer = await FakeSlipRenderer.install(tester);
    renderer.fail = true;
    await _pump(tester);
    await tester.pumpAndSettle();
    expect(find.text('Could not show the document.'), findsOneWidget);

    renderer.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(_firstPage, findsOneWidget);
    expect(find.text('Could not show the document.'), findsNothing);
    expect(renderer.builds, hasLength(2));
  });

  testWidgets('drawn again only when the content changes', (tester) async {
    final renderer = await FakeSlipRenderer.install(tester);
    final scroll = await _pump(tester);
    await tester.pumpAndSettle();

    await _pump(tester, controller: scroll);
    await tester.pumpAndSettle();
    expect(renderer.builds, hasLength(1));

    await _pump(tester, controller: scroll, version: 'b');
    await tester.pumpAndSettle();
    expect(renderer.builds, hasLength(2));

    // Scrolled far away and back: still the same drawing.
    scroll.jumpTo(900);
    await tester.pumpAndSettle();
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(renderer.builds, hasLength(2));
  });

  testWidgets('double-tap zooms in, and back out', (tester) async {
    await FakeSlipRenderer.install(tester);
    await _pump(tester);
    await tester.pumpAndSettle();

    await _doubleTap(tester, tester.getCenter(_firstPage));
    expect(_scale(tester), closeTo(2.5, 0.01));

    await _doubleTap(tester, tester.getCenter(_firstPage));
    expect(_scale(tester), closeTo(1, 0.01));
  });

  testWidgets('pinching zooms', (tester) async {
    await FakeSlipRenderer.install(tester);
    await _pump(tester);
    await tester.pumpAndSettle();
    final centre = tester.getCenter(_firstPage);

    final left = await tester.startGesture(centre - const Offset(30, 0));
    final right = await tester.startGesture(centre + const Offset(30, 0));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await left.moveBy(const Offset(-10, 0));
      await right.moveBy(const Offset(10, 0));
      await tester.pump();
    }
    await left.up();
    await right.up();
    await tester.pumpAndSettle();

    expect(_scale(tester), greaterThan(1.5));
  });

  testWidgets('one finger scrolls the screen, until the page is zoomed', (
    tester,
  ) async {
    await FakeSlipRenderer.install(tester);
    final scroll = await _pump(tester);
    await tester.pumpAndSettle();

    Future<void> dragUp() async {
      final finger = await tester.startGesture(const Offset(180, 300));
      for (var i = 0; i < 10; i++) {
        await finger.moveBy(const Offset(0, -6));
        await tester.pump();
      }
      await finger.up();
      await tester.pumpAndSettle();
    }

    await dragUp();
    expect(scroll.offset, greaterThan(0));

    scroll.jumpTo(0);
    await tester.pump();
    await _doubleTap(tester, tester.getCenter(_firstPage));
    final before = _zoom(tester).value.getTranslation().y;
    await dragUp();

    expect(scroll.offset, 0, reason: 'the screen stays put');
    expect(
      _zoom(tester).value.getTranslation().y,
      lessThan(before),
      reason: 'the page moved under the finger',
    );
  });
}
