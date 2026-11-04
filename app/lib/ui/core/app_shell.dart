import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _select(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final shellIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    return Scaffold(
      body: _ShellVisibility(isCurrent: shellIsCurrent, child: navigationShell),
      // Com fonte do sistema muito grande, "Pessoas" quebrava em duas linhas
      // e empurrava o ícone: a barra de abas cresce no máximo 15%.
      bottomNavigationBar: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: NavigationBar(
          key: const Key('app-nav'),
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: _select,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Amigos',
            ),
            NavigationDestination(
              icon: Icon(Icons.near_me_outlined),
              selectedIcon: Icon(Icons.near_me),
              label: 'Perto',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmark_border),
              selectedIcon: Icon(Icons.bookmark),
              label: 'Quero ir',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_search_outlined),
              selectedIcon: Icon(Icons.person_search),
              label: 'Pessoas',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_circle_outlined),
              selectedIcon: Icon(Icons.account_circle),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}

class AppBranchStack extends StatelessWidget {
  const AppBranchStack({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final shellIsCurrent = _ShellVisibility.isCurrentOf(context);
    return IndexedStack(
      index: currentIndex,
      children: [
        for (var i = 0; i < children.length; i++)
          Offstage(
            offstage: i != currentIndex,
            child: TickerMode(
              enabled: i == currentIndex,
              child: HeroMode(
                enabled: i == currentIndex,
                child: ActiveTab(
                  isActive: i == currentIndex && shellIsCurrent,
                  child: children[i],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ShellVisibility extends InheritedWidget {
  const _ShellVisibility({required this.isCurrent, required super.child});

  final bool isCurrent;

  static bool isCurrentOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_ShellVisibility>()
          ?.isCurrent ??
      true;

  @override
  bool updateShouldNotify(_ShellVisibility oldWidget) =>
      oldWidget.isCurrent != isCurrent;
}

class ActiveTab extends InheritedWidget {
  const ActiveTab({super.key, required this.isActive, required super.child});

  final bool isActive;

  static bool? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActiveTab>()?.isActive;

  @override
  bool updateShouldNotify(ActiveTab oldWidget) =>
      oldWidget.isActive != isActive;
}
