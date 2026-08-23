import 'package:finpilot_assistant/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the FinPilot home screen', (tester) async {
    await tester.pumpWidget(const FinPilotApp());

    expect(find.text('FinPilot Assistant'), findsOneWidget);
    expect(find.text('Budget categories'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Next pay allocation'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Next pay allocation'), findsOneWidget);
  });

  testWidgets('Assistant navigation opens journal entry', (tester) async {
    await tester.pumpWidget(const FinPilotApp());

    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();

    expect(find.text('Tell FinPilot your story'), findsOneWidget);
  });
}
