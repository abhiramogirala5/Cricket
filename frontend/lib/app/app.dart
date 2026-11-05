import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gully_umpire/app/router/app_router.dart';
import 'package:gully_umpire/app/theme/app_theme.dart';

/// The root widget. It has one light theme on purpose: the app is used outdoors in daylight.
class GullyUmpireApp extends ConsumerWidget {
  const GullyUmpireApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GoRouter router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Gully Umpire',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      routerConfig: router,
    );
  }
}
