import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/navigation_providers.dart';
import '../../providers/player_providers.dart';
import '../screens/home_screen.dart';
import '../screens/library_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../widgets/mini_player.dart';

class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  static const _pages = [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    SettingsScreen(),
  ];

  bool _navVisible = true;
  double _lastPixels = 0;

  void _setNavVisible(bool visible) {
    if (_navVisible == visible) return;
    setState(() => _navVisible = visible);
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final pixels = notification.metrics.pixels;
    final delta = pixels - _lastPixels;
    _lastPixels = pixels;
    if (pixels <= 0) {
      _setNavVisible(true);
      return false;
    }
    // Solo ocultamos la cápsula si hay mini reproductor; si no, el usuario se
    // quedaría sin navegación.
    final hasSong = ref.read(currentSongProvider).valueOrNull != null;
    if (delta > 10 && hasSong) {
      _setNavVisible(false);
    } else if (delta < -10) {
      _setNavVisible(true);
    }
    return false;
  }

  void _selectTab(int index, int current) {
    if (index == current) return;
    HapticFeedback.selectionClick();
    _lastPixels = 0;
    _setNavVisible(true);
    ref.read(selectedTabProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(selectedTabProvider);
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          (theme.brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness:
                    theme.brightness == Brightness.dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
      child: Scaffold(
        extendBody: true,
        body: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: SafeArea(
            bottom: false,
            child: IndexedStack(index: index, children: _pages),
          ),
        ),
        bottomNavigationBar: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            12 + media.viewPadding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: _navVisible ? 0 : 74),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                builder: (context, offset, child) => Transform.translate(
                  offset: Offset(0, offset),
                  child: child,
                ),
                child: const MiniPlayer(),
              ),
              const SizedBox(height: 8),
              AnimatedSlide(
                offset: _navVisible ? Offset.zero : const Offset(0, 1.6),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _navVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: _GlassSurface(
                    radius: 26,
                    child: SizedBox(
                      height: 68,
                      child: _MusicNavigationBar(
                        index: index,
                        onSelected: (i) => _selectTab(i, index),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dock de navegación propio: el destino activo se convierte en una cápsula
/// ancha con degradado y etiqueta, mientras el resto queda como iconos limpios.
class _MusicNavigationBar extends StatelessWidget {
  const _MusicNavigationBar({required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  static const _items =
      <({String label, IconData icon, IconData selectedIcon})>[
        (
          label: 'Inicio',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home_rounded,
        ),
        (
          label: 'Buscar',
          icon: Icons.search_outlined,
          selectedIcon: Icons.search_rounded,
        ),
        (
          label: 'Biblioteca',
          icon: Icons.library_music_outlined,
          selectedIcon: Icons.library_music_rounded,
        ),
        (
          label: 'Ajustes',
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings_rounded,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < _items.length; i++)
            _NavDockItem(
              label: _items[i].label,
              icon: _items[i].icon,
              selectedIcon: _items[i].selectedIcon,
              selected: i == index,
              onTap: () => onSelected(i),
            ),
        ],
      ),
    );
  }
}

class _NavDockItem extends StatelessWidget {
  const _NavDockItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final activeColor = colors.onPrimary;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        width: selected ? 118 : 50,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(colors.primary, Colors.white, .16)!,
                    colors.primary,
                  ],
                )
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: .32),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: selected ? 13 : 0),
              child: Row(
                mainAxisAlignment: selected
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Icon(
                      selected ? selectedIcon : icon,
                      key: ValueKey(selected),
                      size: 23,
                      color: selected
                          ? activeColor
                          : colors.onSurfaceVariant.withValues(alpha: .78),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: activeColor,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Superficie tipo "glass": blur del contenido que pasa por detrás, tinte
/// semitransparente, borde suave y sombra flotante.
class _GlassSurface extends StatelessWidget {
  const _GlassSurface({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .38 : .12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: .82),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: .35),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
