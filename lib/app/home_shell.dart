import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/models/program.dart';

/// Bottom-navigation shell for one discipline (strength or rowing). Each
/// discipline has its own instance so their tab stacks stay independent.
class HomeShell extends StatelessWidget {
  const HomeShell({
    super.key,
    required this.navigationShell,
    required this.discipline,
  });

  final StatefulNavigationShell navigationShell;
  final Discipline discipline;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Vandaag',
          ),
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Bibliotheek',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Logboek',
          ),
        ],
      ),
    );
  }
}

/// AppBar leading button that returns to the discipline chooser.
class DisciplineSwitchButton extends StatelessWidget {
  const DisciplineSwitchButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        icon: const Icon(Icons.swap_horiz),
        tooltip: 'Wissel onderdeel',
        onPressed: () => context.go('/'),
      );
}
