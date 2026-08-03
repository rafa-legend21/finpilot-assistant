import 'package:finpilot_assistant/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the FinPilot home screen', (tester) async {
    await tester.pumpWidget(const FinPilotApp());

    expect(find.text('FinPilot Assistant'), findsOneWidget);
    expect(find.text('Budget categories'), findsOneWidget);
    expect(find.text('Next pay allocation'), findsOneWidget);
  });
}
