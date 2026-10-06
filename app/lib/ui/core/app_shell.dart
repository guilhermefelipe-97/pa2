import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Moldura das telas principais: barra de navegação inferior
/// (Amigos · Perto · Quero ir · Pessoas) em volta do branch ativo.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _select(int index) {
    // Tocar na aba ativa volta à raiz dela.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Uma rota fora do shell (detalhe, perfil) por cima deixa as abas
    // invisíveis; ao voltar, a aba atual fica ativa de novo ([ActiveTab]).
    final shellIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    return Scaffold(
      body: _ShellVisibility(isCurrent: shellIsCurrent, child: navigationShell),
      bottomNavigationBar: NavigationBar(
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
        ],
      ),
    );
  }
}

/// Container dos branches: como o `StatefulShellRoute.indexedStack` (estado
/// de cada aba preservado num [IndexedStack]), mas desliga os [Hero]s das
/// abas escondidas — senão um card invisível de outra aba, com a mesma tag
/// do local, "voaria" para o detalhe (e tags repetidas disparam assert) — e
/// avisa cada aba se ela está visível ([ActiveTab]).
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

/// O shell é a rota do topo (nenhuma rota de fora dele por cima).
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

/// Diz a uma aba se ela é a visível: aba selecionada e sem outra rota por
/// cima do shell. Voltar a ficar ativa (troca de aba ou retorno de rota) é
/// quando feed e Pessoas recarregam se seguir/deixar de seguir os deixou
/// desatualizados.
class ActiveTab extends InheritedWidget {
  const ActiveTab({super.key, required this.isActive, required super.child});

  final bool isActive;

  /// `null` fora do shell (ex.: tela montada sozinha num teste).
  static bool? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActiveTab>()?.isActive;

  @override
  bool updateShouldNotify(ActiveTab oldWidget) =>
      oldWidget.isActive != isActive;
}
