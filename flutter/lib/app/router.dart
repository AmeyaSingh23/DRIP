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
        pageBuilder: (context, state) {
          final args = state.extra! as UploadRouteArgs;
          return CustomTransitionPage(
            key: state.pageKey,
            child: UploadScreen(email: args.email),
            transitionDuration: const Duration(milliseconds: 200),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1.0, 0.0),
                  end: Offset.zero,
                ).chain(CurveTween(curve: Curves.easeOutQuad)).animate(animation),
                child: child,
              );
            },
          );
        },
      ),
      GoRoute(
        path: '/outfits/generate',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const OutfitGeneratorScreen(),
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeOutQuad)).animate(animation),
              child: child,
            );
          },
        ),
      ),
      GoRoute(
        path: '/outfits',
        builder: (context, state) => const OutfitsScreen(),
      ),
      GoRoute(
        path: '/outfits/:outfitId',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: OutfitDetailScreen(
            outfitId: state.pathParameters['outfitId']!,
          ),
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeOutQuad)).animate(animation),
              child: child,
            );
          },
        ),
      ),
      GoRoute(
        path: '/wardrobe/items/:itemId',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: ItemDetailScreen(
            itemId: state.pathParameters['itemId']!,
          ),
          transitionDuration: const Duration(milliseconds: 200),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeOutQuad)).animate(animation),
              child: child,
            );
          },
        ),
      ),
    ],
    errorBuilder:
        (context, state) =>
            const Scaffold(body: Center(child: Text('Page not found'))),
  );
});
