import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/wear_bridge.dart';

/// Test de verbinding met het horloge en toon de uitkomst in een snackbar.
Future<void> pingWatch(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Horloge pingen…')));
  final result = await ref.read(wearBridgeProvider).ping();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(result.describe())));
}
