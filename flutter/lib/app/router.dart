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
            initialItems: args.initialItems,
            initialName: args.initialName,
            initialOccasion: args.initialOccasion,
            initialLayout: args.initialLayout,
            editingOutfitId: args.editingOutfitId,
            startCollapsed: args.startCollapsed,
          );
        },
      ),
      GoRoute(
        path: '/wardrobe/upload',
        builder: (context, state) {
          final args = state.extra! as UploadRouteArgs;
          return UploadScreen(email: args.email);
        },
      ),
      GoRoute(
        path: '/outfits/generate',
        builder:
            (context, state) =>
                OutfitGeneratorScreen(),
      ),
      GoRoute(
        path: '/outfits',
        builder:
            (context, state) => OutfitsScreen(),
      ),
      GoRoute(
        path: '/outfits/:outfitId',
        builder:
            (context, state) => OutfitDetailScreen(
              outfitId: state.pathParameters['outfitId']!,
            ),
      ),
      GoRoute(
        path: '/wardrobe/items/:itemId',
        builder:
            (context, state) => ItemDetailScreen(
              itemId: state.pathParameters['itemId']!,
            ),
      ),
    ],
    errorBuilder:
        (context, state) =>
            const Scaffold(body: Center(child: Text('Page not found'))),
  );
});
