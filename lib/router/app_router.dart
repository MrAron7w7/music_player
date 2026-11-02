import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../presentation/navigation/main_scaffold.dart';
import '../presentation/screens/album_detail_screen.dart';
import '../presentation/screens/artist_screen.dart';
import '../presentation/screens/downloads_screen.dart';
import '../presentation/screens/library_collection_screen.dart';
import '../presentation/screens/now_playing_screen.dart';
import '../presentation/screens/playlist_detail_screen.dart';
import '../presentation/screens/playlists_screen.dart';
import '../presentation/screens/stats_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Transición suave "fade-through" para cambios de pestaña.
CustomTransitionPage<void> _fadeThrough(
  BuildContext context,
  GoRouterState state,
  Widget child,
) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 300),
  reverseTransitionDuration: const Duration(milliseconds: 250),
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      ),
);

/// Transición "slide-up" suave para pantallas de detalle.
CustomTransitionPage<void> _slideUp(
  BuildContext context,
  GoRouterState state,
  Widget child,
) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 400),
  reverseTransitionDuration: const Duration(milliseconds: 300),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.18),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
        child: child,
      ),
    );
  },
);

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (c, s) => const MainScaffold()),
    GoRoute(
      path: '/now-playing',
      pageBuilder: (context, state) =>
          _slideUp(context, state, const NowPlayingScreen()),
    ),
    GoRoute(
      path: '/library/favorites',
      pageBuilder: (context, state) => _fadeThrough(
        context,
        state,
        const LibraryCollectionScreen(collection: LibraryCollection.favorites),
      ),
    ),
    GoRoute(
      path: '/library/history',
      pageBuilder: (context, state) => _fadeThrough(
        context,
        state,
        const LibraryCollectionScreen(collection: LibraryCollection.history),
      ),
    ),
    GoRoute(
      path: '/library/playlists',
      pageBuilder: (context, state) =>
          _fadeThrough(context, state, const PlaylistsScreen()),
    ),
    GoRoute(
      path: '/downloads',
      pageBuilder: (context, state) =>
          _fadeThrough(context, state, const DownloadsScreen()),
    ),
    GoRoute(
      path: '/album/:id',
      pageBuilder: (context, state) => _slideUp(
        context,
        state,
        AlbumDetailScreen(albumId: state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/playlist/:id',
      pageBuilder: (context, state) => _slideUp(
        context,
        state,
        PlaylistDetailScreen(playlistId: state.pathParameters['id']!),
      ),
    ),
    GoRoute(
      path: '/stats',
      pageBuilder: (context, state) =>
          _slideUp(context, state, const StatsScreen()),
    ),
    GoRoute(
      path: '/artist/:id',
      pageBuilder: (context, state) => _slideUp(
        context,
        state,
        ArtistScreen(artistId: state.pathParameters['id']!),
      ),
    ),
  ],
);
