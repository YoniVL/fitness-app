import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The app's landing screen: pick strength or rowing. Not persisted — every cold
/// start returns here.
class DisciplineChooserScreen extends StatelessWidget {
  const DisciplineChooserScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text('Fitness Tracker', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text('Wat ga je doen?',
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              Expanded(
                child: _ChoiceCard(
                  icon: Icons.fitness_center,
                  title: 'Krachttraining',
                  subtitle: 'Programma\'s, oefeningen, sets loggen',
                  onTap: () => context.go('/strength/today'),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _ChoiceCard(
                  icon: Icons.rowing,
                  title: 'Roeien',
                  subtitle: 'Plannen, workouts, live sessies',
                  onTap: () => context.go('/rowing/today'),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Instellingen'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.primary),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
