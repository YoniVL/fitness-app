import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/repositories/workout_session_repository.dart';
import '../../domain/models/program.dart';

class LogScreen extends ConsumerWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(recentSessionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Logboek')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(recentSessionsProvider),
        child: sessions.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Fout: $e')),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('Nog geen trainingen gelogd')),
                ],
              );
            }
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) => _SessionTile(summary: list[index]),
            );
          },
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.summary});
  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary.session;
    final dateFmt = DateFormat('EEE d MMM · HH:mm', 'nl');
    final isRowing = s.discipline == Discipline.rowing;
    final duration = s.duration;

    return ListTile(
      leading: Icon(isRowing ? Icons.rowing : Icons.fitness_center),
      title: Text(dateFmt.format(s.startedAt)),
      subtitle: Text([
        if (!isRowing) '${summary.exerciseCount} oefeningen · ${summary.setCount} sets',
        if (!isRowing && summary.totalVolume > 0)
          '${summary.totalVolume.toStringAsFixed(0)} kg volume',
        if (duration != null) _fmtDuration(duration),
        if (!s.isFinished) 'niet afgerond',
      ].join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/log/session/${s.id}'),
    );
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return h > 0 ? '${h}u ${m}m' : '${m}m';
  }
}
