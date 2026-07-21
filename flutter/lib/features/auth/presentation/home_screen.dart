import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calendar/presentation/calendar_screen.dart';
import '../../creative/presentation/creative_space_screen.dart';
import '../../outfits/presentation/outfits_screen.dart';
import '../../wardrobe/presentation/wardrobe_screen.dart';
import 'profile_screen.dart';
import 'auth_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({required this.email, required this.token, super.key});

  final String email;
  final String token;
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  var _index = 0;
  final _tabHistory = <int>[];
  Timer? _sessionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => ref.read(authControllerProvider.notifier).validateSession(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(authControllerProvider.notifier).validateSession();
    }
  }

  void _selectTab(int value) {
    if (value == _index) return;
    setState(() {
      _tabHistory.add(_index);
      _index = value;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _tabHistory.isEmpty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _tabHistory.isNotEmpty) {
        setState(() => _index = _tabHistory.removeLast());
      }
    },
    child: Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: [
          WardrobeScreen(email: widget.email, token: widget.token),
          OutfitsScreen(token: widget.token),
          CreativeSpaceScreen(token: widget.token),
          CalendarScreen(token: widget.token),
          ProfileScreen(email: widget.email, token: widget.token),
        ],
      ),
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: Theme.of(context).colorScheme.surface,
            child: NavigationBar(
              backgroundColor: Colors.transparent,
              indicatorColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              elevation: 0,
              selectedIndex: _index,
              onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checkroom_outlined),
            selectedIcon: Icon(Icons.checkroom),
            label: 'Wardrobe',
          ),
          NavigationDestination(
            icon: Icon(Icons.collections_bookmark_outlined),
            selectedIcon: Icon(Icons.collections_bookmark),
            label: 'Outfits',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_mosaic_outlined),
            selectedIcon: Icon(Icons.auto_awesome_mosaic),
            label: 'Studio',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    ),
  ),
),
    ),
  );
}
