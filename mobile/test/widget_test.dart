import 'package:finpilot_assistant/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the FinPilot home screen', (tester) async {
    await tester.pumpWidget(const FinPilotApp());

    expect(find.text('FinPilot'), findsOneWidget);
    expect(find.text('Your money, in your hands'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('How it works'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('How it works'), findsOneWidget);
    expect(find.text('\$1,284.60'), findsNothing);
  });

  testWidgets('Assistant navigation opens journal entry', (tester) async {
    await tester.pumpWidget(const FinPilotApp());

    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();

    expect(find.text('Tell FinPilot your story'), findsOneWidget);
  });

  testWidgets('home actions fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const FinPilotApp());
    expect(find.text('Tell your story'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('How it works'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
}
