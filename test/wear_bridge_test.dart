import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fitnesstracker/services/wear_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cadans/wear');

  void mockSend(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Uint8List json(Map<String, Object?> m) =>
      Uint8List.fromList(utf8.encode(jsonEncode(m)));

  test('payload krijgt versienummer en is JSON', () {
    final bytes = encodeWearPayload({'id': 'a'});
    expect(jsonDecode(utf8.decode(bytes)), {'v': 1, 'id': 'a'});
  });

  test('WearMessage.json geeft null bij ongeldige inhoud', () {
    final m = WearMessage(
      kind: 'message',
      path: WearPaths.pong,
      nodeId: 'n',
      data: Uint8List.fromList([0xff, 0x00]),
    );
    expect(m.json, isNull);
  });

  test('ping geeft round-trip als pong met hetzelfde id binnenkomt', () async {
    final incoming = StreamController<WearMessage>.broadcast();
    mockSend((call) async {
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['path'], WearPaths.ping);
      final sent = jsonDecode(utf8.decode(args['data']! as Uint8List))
          as Map<String, Object?>;
      scheduleMicrotask(() => incoming.add(WearMessage(
            kind: 'message',
            path: WearPaths.pong,
            nodeId: 'n',
            data: json({'v': 1, 'id': sent['id']}),
          )));
      return {'nodes': 1, 'sent': 1, 'error': null};
    });
    final bridge = WearBridge(method: channel, messages: incoming.stream);
    final result = await bridge.ping(timeout: const Duration(seconds: 2));
    expect(result.ok, isTrue);
    expect(result.describe(), startsWith('Horloge antwoordt'));
    await incoming.close();
  });

  test('ping meldt dat er geen horloge verbonden is', () async {
    mockSend((call) async => {'nodes': 0, 'sent': 0, 'error': 'no_connected_node'});
    final bridge = WearBridge(method: channel, messages: const Stream.empty());
    final result = await bridge.ping(timeout: const Duration(milliseconds: 200));
    expect(result.ok, isFalse);
    expect(result.describe(), 'Geen horloge verbonden');
  });

  test('ping time-out zonder pong', () async {
    mockSend((call) async => {'nodes': 1, 'sent': 1, 'error': null});
    final bridge = WearBridge(
      method: channel,
      messages: StreamController<WearMessage>.broadcast().stream,
    );
    final result = await bridge.ping(timeout: const Duration(milliseconds: 100));
    expect(result.ok, isFalse);
    expect(result.sent.ok, isTrue);
    expect(result.describe(), contains('geen antwoord'));
  });

  test('ontbrekende plugin geeft no_plugin', () async {
    final bridge = WearBridge(method: channel, messages: const Stream.empty());
    final result = await bridge.send(WearPaths.ping);
    expect(result.error, 'no_plugin');
  });
}
