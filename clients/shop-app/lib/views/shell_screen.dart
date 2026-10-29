import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quickeats_shop/core/constants/app_colors.dart';

class ShellScreen extends StatelessWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex(context),
        onDestinationSelected: (i) => _onTap(context, i),
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.primary.withOpacity(0.1),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long), selectedIcon: Icon(Icons.receipt_long, color: AppColors.primary), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.restaurant_menu), selectedIcon: Icon(Icons.restaurant_menu, color: AppColors.primary), label: 'Menu'),
          NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments, color: AppColors.primary), label: 'Earnings'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings, color: AppColors.primary), label: 'Settings'),
        ],
      ),
    );
  }

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/menu')) return 1;
    if (location.startsWith('/earnings')) return 2;
    if (location.startsWith('/settings')) return 3;
    return 0;
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0: context.go('/orders'); break;
      case 1: context.go('/menu'); break;
      case 2: context.go('/earnings'); break;
      case 3: context.go('/settings'); break;
    }
  }
}
