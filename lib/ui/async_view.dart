import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A centred spinner filling a fixed height — the standard "still loading"
/// placeholder for a card or chart.
class LoadingBox extends StatelessWidget {
  const LoadingBox({super.key, this.height = 120});
  final double height;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, child: const Center(child: CircularProgressIndicator()));
}

/// A short inline error message — the standard "couldn't load this" state.
class ErrorBox extends StatelessWidget {
  const ErrorBox({super.key, this.message = 'Kon dit niet laden'});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.error)),
          ),
        ],
      ),
    );
  }
}

/// Collapses the repeated `.when(loading: …, error: …, data: …)` boilerplate
/// into one call with sane, consistent defaults.
extension AsyncValueView<T> on AsyncValue<T> {
  /// `loading` defaults to a [LoadingBox] of [loadingHeight]; `error`
  /// defaults to an [ErrorBox]. Override either for a screen-specific look.
  Widget view(
    Widget Function(T data) data, {
    Widget Function()? loading,
    Widget Function(Object error)? error,
    double loadingHeight = 120,
  }) =>
      when(
        data: data,
        loading: loading ?? () => LoadingBox(height: loadingHeight),
        error: (e, _) => error == null ? const ErrorBox() : error(e),
      );

  /// Nothing while loading or on error — for optional/decorative content that
  /// should simply not appear yet, rather than show a spinner or error text.
  Widget viewOrNothing(Widget Function(T data) data) =>
      maybeWhen(data: data, orElse: () => const SizedBox.shrink());
}
