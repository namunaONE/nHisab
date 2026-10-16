import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhisab/src/core/dates/bs_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('BS flow picks a BS day and returns the AD date',
      (tester) async {
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => FilledButton(
              onPressed: () async {
                result = await BsPicker.pick(
                  ctx,
                  initialDate: DateTime(2026, 10, 15),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Choice sheet, BS preselected (Nepal-first default).
    expect(find.text('Pick date'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    // BS month grid for Ashwin 2083, day 29 preselected.
    expect(find.text('Ashwin 2083'), findsOneWidget);
    await tester.tap(find.text('15'));
    await tester.pump();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

    // BS 2083-06-15 == AD 2026-10-01 (14 days before Oct 15).
    expect(result, DateTime(2026, 10, 1));
  });

  testWidgets('AD flow uses the Material picker', (tester) async {
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => FilledButton(
              onPressed: () async {
                result = await BsPicker.pick(
                  ctx,
                  initialDate: DateTime(2026, 10, 15),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Switch to AD and continue → Material calendar dialog.
    await tester.tap(find.text('AD'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expect(result, isNull); // dismissed without picking
  });
}
