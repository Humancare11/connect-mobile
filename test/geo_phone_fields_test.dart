import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humancare_connect/widgets/consent_checkboxes.dart';
import 'package:humancare_connect/widgets/geo_phone_controller.dart';
import 'package:humancare_connect/widgets/geo_phone_fields.dart';

import 'geo_phone_controller_test.dart' show FakeLocations;

const _states = {
  'IN': ['Goa', 'Kerala'],
  'US': ['Alabama', 'Texas'],
  'CA': ['Ontario'],
  'RU': ['Moscow'],
  'KZ': ['Almaty'],
  'GU': <String>[],
  'AQ': <String>[],
};

Future<GeoPhoneController> _pump(
  WidgetTester tester, {
  required double width,
}) async {
  GeoPhoneController.clearCaches();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);

  final controller = GeoPhoneController(
    locations: FakeLocations(statesByIso: _states),
  );
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(child: GeoPhoneFields(controller: controller)),
        ),
      ),
    ),
  );
  await controller.init();
  await tester.pumpAndSettle();
  return controller;
}

Offset _at(WidgetTester tester, Finder finder) =>
    tester.getTopLeft(finder.first);

void main() {
  testWidgets('phone: stacked in the web order — Country, State, City, Phone', (
    tester,
  ) async {
    await _pump(tester, width: 360);

    final country = _at(tester, find.text('India'));
    final state = _at(tester, find.text('Select state / province'));
    final city = _at(tester, find.text('City'));
    final phone = _at(tester, find.text('Mobile Number'));

    expect(country.dy, lessThan(state.dy));
    expect(state.dy, lessThan(city.dy));
    expect(city.dy, lessThan(phone.dy));
    // Stacked: every field starts at the same left edge.
    expect(state.dx, country.dx);
    expect(city.dx, country.dx);

    // India / +91 by default.
    expect(find.textContaining('+91'), findsOneWidget);
  });

  testWidgets('tablet: Country | State and City | Phone side by side', (
    tester,
  ) async {
    await _pump(tester, width: 900);

    final country = _at(tester, find.text('India'));
    final state = _at(tester, find.text('Select state / province'));
    final city = _at(tester, find.text('City'));
    final phone = _at(tester, find.text('Mobile Number'));

    expect(state.dy, closeTo(country.dy, 2));
    expect(state.dx, greaterThan(country.dx));
    expect(phone.dy, closeTo(city.dy, 4));
    expect(city.dy, greaterThan(country.dy));
  });

  testWidgets(
    'picking a country updates the dial code and clears State; Guam has no states',
    (tester) async {
      final controller = await _pump(tester, width: 360);

      controller.selectState('Kerala');
      await tester.pumpAndSettle();
      expect(find.text('Kerala'), findsOneWidget);

      await tester.tap(find.text('India'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('United States').last);
      await tester.pumpAndSettle();

      expect(controller.countryName, 'United States');
      expect(find.textContaining('+1'), findsOneWidget);
      expect(find.text('Kerala'), findsNothing);
      expect(find.text('Select state / province'), findsOneWidget);

      await tester.tap(find.text('United States'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guam').last);
      await tester.pumpAndSettle();
      expect(find.text('No states available'), findsOneWidget);
    },
  );

  testWidgets('picking a dial code sets the Country', (tester) async {
    final controller = await _pump(tester, width: 360);

    await tester.tap(find.textContaining('+91'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Canada (+1)'));
    await tester.pumpAndSettle();

    expect(controller.countryName, 'Canada');
    expect(find.text('Canada'), findsOneWidget);
  });

  testWidgets('three separate consent checkboxes, all required', (
    tester,
  ) async {
    final consents = ConsentController();
    addTearDown(consents.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConsentCheckboxes(controller: consents)),
      ),
    );

    expect(find.byType(Checkbox), findsNWidgets(3));
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('HIPAA Consent'), findsOneWidget);
    expect(consents.allAccepted, isFalse);

    final boxes = find.byType(Checkbox);
    await tester.tap(boxes.at(0));
    await tester.tap(boxes.at(1));
    await tester.pump();
    expect(consents.allAccepted, isFalse); // HIPAA still unticked
    await tester.tap(boxes.at(2));
    await tester.pump();
    expect(consents.allAccepted, isTrue);
    expect(
      [consents.terms, consents.privacy, consents.hipaa],
      [true, true, true],
    );
  });
}
