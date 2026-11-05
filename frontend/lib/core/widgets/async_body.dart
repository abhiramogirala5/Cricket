import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gully_umpire/core/widgets/error_state.dart';
import 'package:gully_umpire/core/widgets/friendly_error.dart';

/// Shows an [AsyncValue]: a spinner the first time, the content afterwards (it keeps showing the
/// old content while new data loads, so scoring screens never flash), and a friendly error.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      data: (T data) => builder(context, data),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) =>
          ErrorState(message: friendlyError(error), onRetry: onRetry),
    );
  }
}
