import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../calendar/presentation/calendar_screen.dart';
import '../../creative/presentation/creative_space_screen.dart';
import '../../outfits/presentation/outfits_screen.dart';
import '../../wardrobe/presentation/wardrobe_screen.dart';
import 'profile_screen.dart';
import 'auth_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({required this.email,  super.key});

  final String email;
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  var _index = 0;
  final _tabHistory = <int>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(authControllerProvider.notifier).validateSession();
      setState(() {
        _lastPressedAt = null;
      });
    }
  }

  DateTime? _lastPressedAt;

  void _selectTab(int value) {
    if (value == _index) return;
    setState(() {
      if (value == 0) {
        _tabHistory.clear();
      } else {
        _tabHistory.remove(_index);
        _tabHistory.add(_index);
        _tabHistory.remove(value);
      }
      _index = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isDoubleBackActive = _lastPressedAt != null &&
        now.difference(_lastPressedAt!) <= const Duration(seconds: 2);
    final canPop = _index == 0 && _tabHistory.isEmpty && isDoubleBackActive;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_tabHistory.isNotEmpty) {
          setState(() {
            _index = _tabHistory.removeLast();
          });
          return;
        }

        // Wardrobe tab with empty history
        setState(() {
          _lastPressedAt = DateTime.now();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
      extendBody: true,
      body: SlidingIndexedStack(
        index: _index,
        children: [
          WardrobeScreen(email: widget.email, ),
          OutfitsScreen(),
          CreativeSpaceScreen(),
          CalendarScreen(),
          ProfileScreen(email: widget.email, ),
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
}

class SlidingIndexedStack extends StatefulWidget {
  const SlidingIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 120),
  });

  final int index;
  final List<Widget> children;
  final Duration duration;

  @override
  State<SlidingIndexedStack> createState() => _SlidingIndexedStackState();
}

class _SlidingIndexedStackState extends State<SlidingIndexedStack> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _prevIndex;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _prevIndex = widget.index;
    _currentIndex = widget.index;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
  }

  @override
  void didUpdateWidget(SlidingIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != _currentIndex) {
      setState(() {
        _prevIndex = _currentIndex;
        _currentIndex = widget.index;
      });
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        final curveProgress = Curves.easeOutQuad.transform(progress);
        
        return Stack(
          children: List.generate(widget.children.length, (i) {
            final isCurrent = i == _currentIndex;
            final isPrev = i == _prevIndex;
            final isTransitioning = _controller.isAnimating && (isCurrent || isPrev);
            final isVisible = isCurrent || isTransitioning;

            double dx = 0.0;
            if (isPrev && _prevIndex != _currentIndex) {
              dx = _currentIndex > _prevIndex ? -curveProgress : curveProgress;
            } else if (isCurrent && _prevIndex != _currentIndex) {
              dx = _currentIndex > _prevIndex ? (1.0 - curveProgress) : -(1.0 - curveProgress);
            }

            return FractionalTranslation(
              translation: Offset(dx, 0.0),
              child: Offstage(
                offstage: !isVisible,
                child: RepaintBoundary(
                  child: widget.children[i],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}


