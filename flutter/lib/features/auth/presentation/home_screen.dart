import 'package:flutter/material.dart';

import '../../calendar/presentation/calendar_screen.dart';
import '../../outfits/presentation/outfits_screen.dart';
import '../../wardrobe/presentation/wardrobe_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.email, required this.token, super.key});

  final String email;
  final String token;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _index = 0;
  final _tabHistory = <int>[];

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
      body: IndexedStack(
        index: _index,
        children: [
          WardrobeScreen(email: widget.email, token: widget.token),
          OutfitsScreen(token: widget.token),
          CalendarScreen(token: widget.token),
          ProfileScreen(email: widget.email),
        ],
      ),
      bottomNavigationBar: NavigationBar(
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
  );
}
