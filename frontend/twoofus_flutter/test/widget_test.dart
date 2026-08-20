import 'package:flutter_test/flutter_test.dart';
import 'package:twoofus_flutter/main.dart';

void main() {
  testWidgets('App root initializes smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TwoOfUsApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TwoOfUsApp), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });
}
