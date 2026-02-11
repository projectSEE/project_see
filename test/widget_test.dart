// Basic widget test for Blind Assist app

import 'package:flutter_test/flutter_test.dart';
import 'package:blind_assist/main.dart';

void main() {
  testWidgets('App starts successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BlindAssistApp());

    // Verify the app launches without error
    expect(find.byType(BlindAssistApp), findsOneWidget);
  });
}
