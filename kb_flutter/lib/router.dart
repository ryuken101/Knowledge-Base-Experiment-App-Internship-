import 'package:go_router/go_router.dart';

import 'screens/home_screen.dart';

/// Single route for Stage 1. Stage 2 (version history) adds child routes here.
final appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
  ],
);
