import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LaMaisonDeMinisoApp()));
}

class LaMaisonDeMinisoApp extends ConsumerWidget {
  const LaMaisonDeMinisoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'La Maison de Miniso',
    debugShowCheckedModeBanner: false,
    theme: buildLaMaisonTheme(),
    routerConfig: ref.watch(appRouterProvider),
  );
}
