import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:drip/main.dart';

void main() {
  testWidgets('DRIP launches into the auth gate', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: DripApp()));
    await tester.pump();

    expect(find.text('DRIP'), findsOneWidget);
  });
}
