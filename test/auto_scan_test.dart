/// AutoScanController: hands-free scanning lifecycle with scripted frame
/// streams — no network, no timers longer than a few hundred ms.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pokemon_strategy_app/src/recognition/auto_scan.dart';

void main() {
  final frame = Uint8List.fromList([1, 2, 3]);

  test('preview phase scans slowly, battle phase scans fast', () async {
    var phase = AutoScanPhase.preview;
    final scans = <AutoScanPhase>[];
    StreamController<Uint8List>? feed;
    final controller = AutoScanController(
      framesOf: (_) {
        feed = StreamController<Uint8List>();
        // Emit a fresh frame every 10 ms.
        Timer.periodic(const Duration(milliseconds: 10), (t) {
          if (feed!.isClosed) {
            t.cancel();
          } else {
            feed!.add(frame);
          }
        });
        return feed!.stream;
      },
      urlOf: () => Uri.parse('http://rig:81/stream'),
      phaseOf: () => phase,
      onFrame: (bytes, p) async => scans.add(p),
      previewInterval: const Duration(milliseconds: 120),
      battleInterval: const Duration(milliseconds: 30),
      tickGranularity: const Duration(milliseconds: 5),
    );
    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final previewScans = scans.where((p) => p == AutoScanPhase.preview).length;
    expect(previewScans, greaterThanOrEqualTo(2));
    expect(previewScans, lessThanOrEqualTo(5),
        reason: 'preview must respect the slow interval');

    phase = AutoScanPhase.battle;
    scans.clear();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(scans.where((p) => p == AutoScanPhase.battle).length,
        greaterThanOrEqualTo(5),
        reason: 'battle phase ticks several times per second');
    controller.stop();
    await feed?.close();
  });

  test('no saved URL: idles with a helpful status, never scans', () async {
    var scanned = 0;
    final controller = AutoScanController(
      framesOf: (_) => const Stream.empty(),
      urlOf: () => null,
      phaseOf: () => AutoScanPhase.preview,
      onFrame: (bytes, p) async => scanned++,
      tickGranularity: const Duration(milliseconds: 5),
      reconnectDelay: const Duration(milliseconds: 20),
    );
    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(scanned, 0);
    expect(controller.status.value.message, contains('No rig address'));
    controller.stop();
  });

  test('pause releases the stream; resume reconnects', () async {
    var connects = 0;
    final controller = AutoScanController(
      framesOf: (_) {
        connects++;
        return Stream<Uint8List>.periodic(
            const Duration(milliseconds: 10), (_) => frame);
      },
      urlOf: () => Uri.parse('http://rig:81/stream'),
      phaseOf: () => AutoScanPhase.preview,
      onFrame: (bytes, p) async {},
      previewInterval: const Duration(milliseconds: 30),
      tickGranularity: const Duration(milliseconds: 5),
    );
    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(connects, 1);
    controller.pause('manual capture open');
    expect(controller.isPaused, isTrue);
    expect(controller.status.value.paused, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    controller.resume();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(connects, 2, reason: 'resume opens a fresh stream');
    expect(controller.isPaused, isFalse);
    controller.stop();
  });

  test('a dead stream reconnects by itself', () async {
    var connects = 0;
    final controller = AutoScanController(
      framesOf: (_) {
        connects++;
        // First connection dies immediately; later ones live.
        if (connects == 1) {
          return Stream<Uint8List>.error(Exception('connection refused'));
        }
        return Stream<Uint8List>.periodic(
            const Duration(milliseconds: 10), (_) => frame);
      },
      urlOf: () => Uri.parse('http://rig:81/stream'),
      phaseOf: () => AutoScanPhase.preview,
      onFrame: (bytes, p) async {},
      previewInterval: const Duration(milliseconds: 30),
      reconnectDelay: const Duration(milliseconds: 30),
      tickGranularity: const Duration(milliseconds: 5),
    );
    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(connects, greaterThanOrEqualTo(2));
    expect(controller.status.value.connected, isTrue);
    controller.stop();
  });

  test('a scan failure is caught and reported, scanning continues', () async {
    var calls = 0;
    final controller = AutoScanController(
      framesOf: (_) => Stream<Uint8List>.periodic(
          const Duration(milliseconds: 10), (_) => frame),
      urlOf: () => Uri.parse('http://rig:81/stream'),
      phaseOf: () => AutoScanPhase.battle,
      onFrame: (bytes, p) async {
        calls++;
        if (calls == 1) throw StateError('boom');
      },
      battleInterval: const Duration(milliseconds: 30),
      tickGranularity: const Duration(milliseconds: 5),
    );
    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(calls, greaterThanOrEqualTo(3),
        reason: 'one bad frame must not stop the loop');
    controller.stop();
  });
}
