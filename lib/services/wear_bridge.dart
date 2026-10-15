import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Paden van het Cadans-horlogeprotocol (versie 1). Moet gelijk blijven met
/// `WearBridge.kt` en de horloge-app; zie `docs/cadans-wear-design.md` in de
/// smartwatch-repo.
class WearPaths {
  const WearPaths._();

  static const prefix = '/cadans/v1/';
  static const ping = '${prefix}ping';
  static const pong = '${prefix}pong';
}

/// Eén bericht (`kind == 'message'`) of data-item (`kind == 'data'`) van het horloge.
class WearMessage {
  const WearMessage({
    required this.kind,
    required this.path,
    required this.nodeId,
    required this.data,
  });

  final String kind;
  final String path;
  final String nodeId;
  final Uint8List data;

  factory WearMessage.fromEvent(Object? raw) {
    final map = Map<Object?, Object?>.from(raw! as Map);
    return WearMessage(
      kind: map['kind'] as String? ?? 'message',
      path: map['path'] as String? ?? '',
      nodeId: map['nodeId'] as String? ?? '',
      data: map['data'] as Uint8List? ?? Uint8List(0),
    );
  }

  /// De JSON-inhoud, of null als het geen geldige JSON-object is.
  Map<String, Object?>? get json {
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is Map<String, Object?>) return decoded;
    } catch (_) {
      // Geen JSON: val terug op null.
    }
    return null;
  }
}

/// Uitkomst van één `send` naar alle verbonden horloges.
class WearSendResult {
  const WearSendResult({required this.nodes, required this.sent, this.error});

  final int nodes;
  final int sent;
  final String? error;

  bool get ok => sent > 0;

  factory WearSendResult.fromMap(Map<String, Object?> map) => WearSendResult(
        nodes: map['nodes'] as int? ?? 0,
        sent: map['sent'] as int? ?? 0,
        error: map['error'] as String?,
      );
}

/// Uitkomst van een ping/pong-test.
class PingResult {
  const PingResult({required this.sent, this.roundTrip});

  final WearSendResult sent;
  final Duration? roundTrip;

  bool get ok => roundTrip != null;

  /// Korte Nederlandse uitleg voor in de UI.
  String describe() {
    if (ok) return 'Horloge antwoordt (${roundTrip!.inMilliseconds} ms)';
    switch (sent.error) {
      case 'no_connected_node':
        return 'Geen horloge verbonden';
      case 'no_plugin':
        return 'Horlogekoppeling niet beschikbaar op dit toestel';
      case null:
        return 'Bericht verstuurd, maar geen antwoord van het horloge';
      default:
        return 'Versturen mislukt (${sent.error})';
    }
  }
}

/// JSON-payload met versienummer, als bytes voor de Data Layer.
Uint8List encodeWearPayload(Map<String, Object?> payload) =>
    Uint8List.fromList(utf8.encode(jsonEncode({'v': 1, ...payload})));

/// Dart-kant van de Kotlin-brug (`WearBridgePlugin`). Alleen Android.
class WearBridge {
  WearBridge({MethodChannel? method, Stream<WearMessage>? messages})
      : _method = method ?? const MethodChannel('cadans/wear'),
        _messages = messages;

  final MethodChannel _method;
  final Stream<WearMessage>? _messages;

  /// Binnenkomende berichten en data-items van het horloge.
  Stream<WearMessage> get messages =>
      _messages ??
      const EventChannel('cadans/wear/events')
          .receiveBroadcastStream()
          .map(WearMessage.fromEvent);

  Future<WearSendResult> send(
    String path, [
    Map<String, Object?> payload = const {},
  ]) async {
    try {
      final raw = await _method.invokeMapMethod<String, Object?>('send', {
        'path': path,
        'data': encodeWearPayload(payload),
      });
      return WearSendResult.fromMap(raw ?? const {});
    } on MissingPluginException {
      return const WearSendResult(nodes: 0, sent: 0, error: 'no_plugin');
    } on PlatformException catch (e) {
      return WearSendResult(nodes: 0, sent: 0, error: e.code);
    }
  }

  /// Stuurt een ping en wacht op een `pong` met hetzelfde id.
  Future<PingResult> ping({Duration timeout = const Duration(seconds: 5)}) async {
    final id = Random().nextInt(1 << 30).toString();
    final started = Stopwatch()..start();
    final pong = Completer<void>();
    final sub = messages.listen((m) {
      if (m.path == WearPaths.pong && m.json?['id'] == id && !pong.isCompleted) {
        pong.complete();
      }
    });
    var sent = const WearSendResult(nodes: 0, sent: 0);
    try {
      sent = await send(WearPaths.ping, {
        'id': id,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      if (!sent.ok) return PingResult(sent: sent);
      await pong.future.timeout(timeout);
      return PingResult(sent: sent, roundTrip: started.elapsed);
    } on TimeoutException {
      return PingResult(sent: sent);
    } finally {
      await sub.cancel();
    }
  }
}

final wearBridgeProvider = Provider<WearBridge>((ref) => WearBridge());
