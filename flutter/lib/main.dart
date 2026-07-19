import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: DripApp()));
}

class DripApp extends ConsumerWidget {
  const DripApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'DRIP',
    debugShowCheckedModeBanner: false,
    theme: buildDripTheme(),
    routerConfig: ref.watch(appRouterProvider),
  );
}
