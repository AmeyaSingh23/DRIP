import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/auth_gate.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/outfits/presentation/outfit_generator_screen.dart';
import '../features/outfits/presentation/outfits_screen.dart';
import '../features/wardrobe/presentation/item_detail_screen.dart';
import '../features/wardrobe/presentation/upload_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthGate()),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/wardrobe/upload',
        builder:
            (context, state) => UploadScreen(token: state.extra! as String),
      ),
      GoRoute(
        path: '/outfits/generate',
        builder:
            (context, state) =>
                OutfitGeneratorScreen(token: state.extra! as String),
      ),
      GoRoute(
        path: '/outfits',
        builder:
            (context, state) => OutfitsScreen(token: state.extra! as String),
      ),
      GoRoute(
        path: '/wardrobe/items/:itemId',
        builder:
            (context, state) => ItemDetailScreen(
              itemId: state.pathParameters['itemId']!,
              token: state.extra! as String,
            ),
      ),
    ],
    errorBuilder:
        (context, state) =>
            Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
  );
});
