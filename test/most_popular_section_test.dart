import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humancare_connect/widgets/home/most_popular_section.dart';

Future<void> _pump(
  WidgetTester tester, {
  String searchQuery = '',
  double textScale = 1,
}) {
  return tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(
          children: [
            Padding(
              // Same gutter as the home screen.
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: MostPopularSection(searchQuery: searchQuery),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders both cards', (tester) async {
    await _pump(tester);

    expect(find.text('Most Popular'), findsOneWidget);
    expect(find.text('General Practitioner'), findsOneWidget);
    expect(find.text('Pediatrics'), findsOneWidget);
  });

  testWidgets('hides itself when the search matches no card', (tester) async {
    await _pump(tester, searchQuery: 'dermatology');

    expect(find.text('Most Popular'), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    final section = find.byType(MostPopularSection, skipOffstage: false);
    expect(tester.getSize(section).height, 0);
  });

  testWidgets('does not overflow at 320 px with 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(tester, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(find.text('General Practitioner'), findsOneWidget);
    expect(find.text('Pediatrics'), findsOneWidget);
  });
}
