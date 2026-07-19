import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/auth_gate.dart';
import '../features/creative/presentation/creative_space_screen.dart';
import '../features/outfits/presentation/outfit_generator_screen.dart';
import '../features/outfits/presentation/outfit_detail_screen.dart';
import '../features/outfits/presentation/outfits_screen.dart';
import '../features/wardrobe/presentation/item_detail_screen.dart';
import '../features/wardrobe/presentation/upload_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const AuthGate()),
      GoRoute(
        path: '/creative',
        builder: (context, state) {
          final args = state.extra! as CreativeRouteArgs;
          return CreativeSpaceScreen(
            token: args.token,
            initialItems: args.initialItems,
            startCollapsed: args.startCollapsed,
          );
        },
      ),
      GoRoute(
        path: '/wardrobe/upload',
        builder: (context, state) {
          final args = state.extra! as UploadRouteArgs;
          return UploadScreen(token: args.token, email: args.email);
        },
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
        path: '/outfits/:outfitId',
        builder:
            (context, state) => OutfitDetailScreen(
              outfitId: state.pathParameters['outfitId']!,
              token: state.extra! as String,
            ),
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
