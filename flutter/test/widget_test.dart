import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:la_maison_de_miniso/main.dart';

void main() {
  testWidgets('La Maison de Miniso launches into the auth gate', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: LaMaisonDeMinisoApp()));
    await tester.pump();

    expect(find.text('La Maison de Miniso'), findsOneWidget);
  });
}
