import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'features/wardrobe/data/background_upload_queue.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(backgroundUploadDispatcher);
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
