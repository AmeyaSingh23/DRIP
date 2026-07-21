import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const LaMaisonDeMinisoApp(),
    ),
  );
}

class LaMaisonDeMinisoApp extends ConsumerWidget {
  const LaMaisonDeMinisoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark || 
        (themeMode == ThemeMode.system && MediaQuery.of(context).platformBrightness == Brightness.dark);

    return MaterialApp.router(
      title: 'La Maison de Miniso',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) {
        return Material(
          color: isDark ? const Color(0xFF2A1B22) : const Color(0xFFFFF5F7),
          child: Stack(
            children: [
              // Global background so every screen has the leopard print natively
              Positioned.fill(
                child: Opacity(
                  opacity: isDark ? 0.35 : 0.25,
                  child: Image.asset(
                    isDark
                        ? 'assets/images/dark_leopard_texture.png'
                        : 'assets/images/leopard_texture.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              if (child != null) child,
            ],
          ),
        );
      },
    );
  }
}
