import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

import '../presentation/navigation/main_scaffold.dart';
import '../presentation/screens/now_playing_screen.dart';
import '../presentation/screens/playlist_detail_screen.dart';
import '../presentation/screens/album_detail_screen.dart';
import '../presentation/screens/downloads_screen.dart';
import '../presentation/screens/library_collection_screen.dart';
import '../presentation/screens/playlists_screen.dart';
import '../presentation/screens/stats_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (c, s) => const MainScaffold()),
    GoRoute(
      path: '/now-playing',
      pageBuilder: (context, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        child: const NowPlayingScreen(),
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: SlideTransition(
                position:
                    Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                        .chain(CurveTween(curve: Curves.easeOutCubic))
                        .animate(animation),
                child: child,
              ),
            ),
      ),
    ),
    GoRoute(
      path: '/library/favorites',
      builder: (c, s) => const LibraryCollectionScreen(
        collection: LibraryCollection.favorites,
      ),
    ),
    GoRoute(
      path: '/library/history',
      builder: (c, s) =>
          const LibraryCollectionScreen(collection: LibraryCollection.history),
    ),
    GoRoute(
      path: '/library/playlists',
      builder: (c, s) => const PlaylistsScreen(),
    ),
    GoRoute(path: '/downloads', builder: (c, s) => const DownloadsScreen()),
    GoRoute(
      path: '/album/:id',
      builder: (c, s) => AlbumDetailScreen(albumId: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/playlist/:id',
      builder: (c, s) =>
          PlaylistDetailScreen(playlistId: s.pathParameters['id']!),
    ),
    GoRoute(path: '/stats', builder: (c, s) => const StatsScreen()),
  ],
);
