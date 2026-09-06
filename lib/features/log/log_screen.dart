import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/home_shell.dart';
import '../../data/repositories/rowing_repository.dart';
import '../../data/repositories/workout_session_repository.dart';
import '../../domain/models/program.dart';
import '../../domain/rowing_format.dart';
import '../../ui/async_view.dart';
import '../../ui/confirm_dialog.dart';
import '../../ui/empty_state.dart';

class LogScreen extends ConsumerWidget {
  const LogScreen({super.key, required this.discipline});

  final Discipline discipline;

  String get _base =>
      discipline == Discipline.rowing ? '/rowing/log' : '/strength/log';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(recentSessionsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const DisciplineSwitchButton(),
        title: const Text('Logboek'),
        actions: [
          IconButton(
            icon: const Icon(Icons.insights_outlined),
            tooltip: 'Voortgang',
            onPressed: () => context.push('$_base/progress'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(recentSessionsProvider),
        child: sessions.view(
          (all) {
            final list = all
                .where((s) => s.session.discipline == discipline)
                .toList();
            if (list.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState('Nog niks gelogd'),
                ],
              );
            }
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final summary = list[index];
                return Dismissible(
                  key: ValueKey(summary.session.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Theme.of(context).colorScheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: Icon(Icons.delete,
                        color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                  confirmDismiss: (_) => _confirmDelete(context),
                  onDismissed: (_) async {
                    await ref
                        .read(workoutSessionRepositoryProvider)
                        .deleteSession(summary.session.id);
                    ref.invalidate(recentSessionsProvider);
                    if (summary.session.discipline == Discipline.rowing) {
                      for (final p in rowingProgressProviders) {
                        ref.invalidate(p);
                      }
                    }
                  },
                  child: _SessionTile(summary: summary, basePath: _base),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

Future<bool> _confirmDelete(BuildContext context) => confirmDialog(
      context,
      title: 'Sessie verwijderen?',
      message: 'Dit kan niet ongedaan worden gemaakt.',
      confirmLabel: 'Verwijderen',
      destructive: true,
    );

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.summary, required this.basePath});
  final SessionSummary summary;
  final String basePath;

  @override
  Widget build(BuildContext context) {
    final s = summary.session;
    final dateFmt = DateFormat('EEE d MMM · HH:mm', 'nl');
    final isRowing = s.discipline == Discipline.rowing;
    final duration = s.duration;
    final ongoing = !s.isFinished;

    final muscles = summary.muscleGroups.take(3).join(', ');
    final rowing = summary.rowing;
    final tile = ListTile(
      leading: Icon(
        ongoing
            ? Icons.pending_outlined
            : (isRowing ? Icons.rowing : Icons.fitness_center),
      ),
      title: Text(dateFmt.format(s.startedAt)),
      subtitle: Text([
        if (isRowing && rowing != null) ...[
          distanceLabel(rowing.distanceM),
          hmsLabel(rowing.duration),
          if (rowing.avgPaceSec500 != null)
            '~${paceLabel(rowing.avgPaceSec500)}',
        ] else ...[
          if (!isRowing)
            '${summary.exerciseCount} oefeningen · ${summary.setCount} sets',
          if (!isRowing && muscles.isNotEmpty) muscles,
          if (duration != null) _fmtDuration(duration),
        ],
        if (ongoing) 'bezig',
      ].join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('$basePath/session/${s.id}'),
    );
    return ongoing
        ? Opacity(opacity: 0.55, child: tile)
        : tile;
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}u ${m}m' : '${m}m';
  }
}
