import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/program_repository.dart';
import '../../domain/models/program.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strength = ref.watch(strengthTemplatesProvider);
    final rowing = ref.watch(rowingTemplatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bibliotheek')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.fitness_center),
            title: const Text('Oefeningendatabase'),
            subtitle: const Text('Alle oefeningen, per spiergroep'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/library/exercises'),
          ),
          const Divider(),
          _sectionHeader(context, 'Krachtprogramma\'s'),
          strength.when(
            loading: () => const _LoadingTile(),
            error: (e, _) => _ErrorTile('$e'),
            data: (programs) => Column(
              children: programs.map((p) => _ProgramTile(program: p)).toList(),
            ),
          ),
          _sectionHeader(context, 'Roeiprogramma\'s'),
          rowing.when(
            loading: () => const _LoadingTile(),
            error: (e, _) => _ErrorTile('$e'),
            data: (programs) => Column(
              children: programs.map((p) => _ProgramTile(program: p)).toList(),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _ProgramTile extends StatelessWidget {
  const _ProgramTile({required this.program});
  final Program program;

  @override
  Widget build(BuildContext context) {
    final isRowing = program.discipline == Discipline.rowing;
    return ListTile(
      leading: Icon(isRowing ? Icons.rowing : Icons.fitness_center),
      title: Text(program.name),
      subtitle: Text(isRowing ? 'Roeien' : 'Kracht'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push('/library/program/${program.id}'),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Fout: $message'),
      );
}
