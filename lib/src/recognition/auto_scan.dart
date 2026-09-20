/// Hands-free scanning from the camera rig. Pure Dart — the MJPEG stream
/// comes in through an injected `framesOf` (NetworkCameraClient.frames in
/// the app, scripted streams in tests), so the whole lifecycle is
/// unit-testable with no network.
///
/// Lifecycle (wired up by AppState):
///   * A battle starts -> the controller connects to the saved rig address
///     and keeps the latest frame.
///   * While picks are NOT locked, it scans the frame every
///     [previewInterval] as a team-preview scan (fills the six enemy boxes;
///     confirmed boxes are never overwritten — see AppState._mergePreview).
///   * The moment picks are locked it switches to [battleInterval] OCR
///     ticks: read every name and message on screen, update who is on the
///     field, confirm moves/items/abilities, collect speed-order evidence.
///   * The battle ends -> stop().
///
/// The rig's ESP32 serves ONE stream client at a time, so the manual
/// capture screen pauses the controller while it is open (pause()
/// disconnects; resume() reconnects).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueNotifier;

/// What the next automatic scan will do.
enum AutoScanPhase { off, preview, battle }

/// Snapshot of the controller for the status chip.
class AutoScanStatus {
  final bool running;
  final bool paused;
  final bool connected;
  final AutoScanPhase phase;
  final String message;
  final DateTime? lastScanAt;
  final int scans;

  const AutoScanStatus({
    this.running = false,
    this.paused = false,
    this.connected = false,
    this.phase = AutoScanPhase.off,
    this.message = '',
    this.lastScanAt,
    this.scans = 0,
  });
}

class AutoScanController {
  AutoScanController({
    required this.framesOf,
    required this.urlOf,
    required this.phaseOf,
    required this.onFrame,
    this.previewInterval = const Duration(seconds: 5),
    this.battleInterval = const Duration(milliseconds: 500),
    this.reconnectDelay = const Duration(seconds: 5),
    Duration? tickGranularity,
  }) : _granularity = tickGranularity ?? const Duration(milliseconds: 100);

  /// MJPEG frames for a URL (NetworkCameraClient.frames in the app).
  final Stream<Uint8List> Function(Uri url) framesOf;

  /// Current rig address; null = not configured (controller idles).
  final Uri? Function() urlOf;

  /// What a scan should do right now (preview until picks locked, then
  /// battle). [AutoScanPhase.off] skips ticks without disconnecting.
  final AutoScanPhase Function() phaseOf;

  /// Runs one scan. Exceptions are caught and shown in the status.
  final Future<void> Function(Uint8List frame, AutoScanPhase phase) onFrame;

  final Duration previewInterval;
  final Duration battleInterval;
  final Duration reconnectDelay;
  final Duration _granularity;

  final ValueNotifier<AutoScanStatus> status =
      ValueNotifier(const AutoScanStatus());

  StreamSubscription<Uint8List>? _sub;
  Timer? _ticker;
  Timer? _reconnect;
  Uint8List? _frame;
  DateTime? _frameAt;
  DateTime _due = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;
  bool _paused = false;
  bool _stopped = false;
  int _scans = 0;

  bool get isRunning => !_stopped && _ticker != null;
  bool get isPaused => _paused;

  void start() {
    if (_stopped) return;
    _ticker ??= Timer.periodic(_granularity, (_) => _tick());
    _connect();
  }

  /// Disconnects and stops scanning until [resume] — used while the manual
  /// capture screen is open, because the rig serves one client at a time.
  void pause([String reason = 'paused']) {
    _paused = true;
    _reconnect?.cancel();
    _disconnect();
    _publish(message: reason);
  }

  void resume() {
    if (_stopped || !_paused) return;
    _paused = false;
    _reconnect?.cancel(); // _connect below supersedes any pending retry
    _connect();
  }

  void stop() {
    _stopped = true;
    _ticker?.cancel();
    _ticker = null;
    _reconnect?.cancel();
    _disconnect();
    _publish(message: 'stopped');
  }

  // ------------------------------------------------------------ stream --

  void _connect() {
    if (_stopped || _paused) return;
    final url = urlOf();
    if (url == null) {
      _publish(message: 'No rig address saved — set it in Settings '
          'or use Manually scan.');
      _scheduleReconnect(); // the user may save an address mid-battle
      return;
    }
    _disconnect();
    _publish(message: 'Connecting to $url…');
    _sub = framesOf(url).listen(
      (frame) {
        _frame = frame;
        _frameAt = DateTime.now();
        if (!status.value.connected) _publish();
      },
      onError: (Object e) {
        _sub?.cancel(); // don't let this stream's onDone orphan a reconnect
        _sub = null;
        _frame = null;
        _publish(message: 'Rig unreachable ($e) — retrying…');
        _scheduleReconnect();
      },
      onDone: () {
        _sub = null;
        _frame = null;
        _publish(message: 'Rig stream ended — retrying…');
        _scheduleReconnect();
      },
    );
  }

  void _disconnect() {
    _sub?.cancel();
    _sub = null;
    _frame = null;
    _frameAt = null;
  }

  void _scheduleReconnect() {
    if (_stopped || _paused) return;
    _reconnect?.cancel();
    _reconnect = Timer(reconnectDelay, _connect);
  }

  // -------------------------------------------------------------- ticks --

  Duration _intervalFor(AutoScanPhase phase) =>
      phase == AutoScanPhase.battle ? battleInterval : previewInterval;

  Future<void> _tick() async {
    if (_stopped || _paused || _busy) return;
    final phase = phaseOf();
    if (phase == AutoScanPhase.off) return;
    final now = DateTime.now();
    if (now.isBefore(_due)) return;
    final frame = _frame;
    final at = _frameAt;
    if (frame == null || at == null) return;
    // A frame older than a few intervals means the stream stalled — don't
    // keep rescanning the same stale image.
    if (now.difference(at) > _intervalFor(phase) * 3 + const Duration(seconds: 2)) {
      return;
    }
    _busy = true;
    _due = now.add(_intervalFor(phase));
    try {
      await onFrame(frame, phase);
      _scans++;
      _publish(lastScanAt: DateTime.now());
    } catch (e) {
      _publish(message: 'Scan failed: $e');
    } finally {
      _busy = false;
    }
  }

  void _publish({String? message, DateTime? lastScanAt}) {
    status.value = AutoScanStatus(
      running: isRunning,
      paused: _paused,
      connected: _sub != null && _frame != null,
      phase: _stopped || _paused ? AutoScanPhase.off : phaseOf(),
      message: message ?? '',
      lastScanAt: lastScanAt ?? status.value.lastScanAt,
      scans: _scans,
    );
  }
}
