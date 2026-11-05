import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gully_umpire/app/app.dart';
import 'package:gully_umpire/app/theme/app_theme.dart';
import 'package:gully_umpire/core/config/app_config.dart';
import 'package:gully_umpire/core/di/core_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final AppConfig config = await AppConfig.load();

  // A production build with a broken configuration must not start half-working.
  final List<String> problems = config.validate();
  if (config.isProduction && problems.isNotEmpty) {
    runApp(_ConfigProblemApp(problems: problems));
    return;
  }

  runApp(
    ProviderScope(
      overrides: <Override>[appConfigProvider.overrideWithValue(config)],
      child: const GullyUmpireApp(),
    ),
  );
}

/// Shown instead of the app when a production build is configured wrongly.
class _ConfigProblemApp extends StatelessWidget {
  const _ConfigProblemApp({required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gully Umpire',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.build_circle_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  'This build is not set up correctly',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                for (final String problem in problems) Text('• $problem'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
