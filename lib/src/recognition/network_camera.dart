/// MJPEG network-camera client for the Switch camera rig — the XIAO
/// ESP32S3 Sense streaming at `http://<ip>:81/stream` — and for any other
/// multipart/x-mixed-replace MJPEG source (e.g. the IP Webcam Android app
/// at `http://<ip>:8080/video`, handy for testing before the rig exists).
///
/// Frame extraction scans for raw JPEG SOI/EOI markers instead of trusting
/// multipart boundary strings, so it tolerates every server dialect.
/// Alongside `cloud_vision_recognizer.dart`, this is the only file allowed
/// to touch the network (see the plugin-isolation rule in CLAUDE.md).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class NetworkCameraException implements Exception {
  final String message;
  NetworkCameraException(this.message);

  @override
  String toString() => message;
}

/// Turn whatever the user typed into a stream URL.
///
/// * `192.168.4.2`            -> `http://192.168.4.2:81/stream`
/// * `192.168.4.2:8080/video` -> `http://192.168.4.2:8080/video`
/// * a full URL passes through untouched.
///
/// Returns null for blank input.
Uri? normalizeStreamUrl(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final withScheme = text.contains('://') ? text : 'http://$text';
  final uri = Uri.tryParse(withScheme);
  if (uri == null || uri.host.isEmpty) return null;
  final bare = uri.path.isEmpty || uri.path == '/';
  if (bare && !uri.hasPort) {
    return uri.replace(port: 81, path: '/stream');
  }
  if (bare) {
    return uri.replace(path: '/stream');
  }
  return uri;
}

/// Incremental JPEG-frame extractor: feed arbitrary byte chunks in, get
/// complete JPEG frames out. Pure logic — unit-tested with no network.
class MjpegFrameParser {
  MjpegFrameParser({this.maxBuffer = 4 << 20});

  /// Safety valve: if this many bytes accumulate without a complete frame,
  /// the buffer is dropped (a garbage stream, not a camera).
  final int maxBuffer;

  final List<int> _pending = [];
  int _scanFrom = 0;

  /// Feed one chunk; returns every frame completed by it (usually 0 or 1).
  List<Uint8List> add(List<int> chunk) {
    _pending.addAll(chunk);
    final frames = <Uint8List>[];
    while (true) {
      final frame = _extractOne();
      if (frame == null) break;
      frames.add(frame);
    }
    if (_pending.length > maxBuffer) {
      _pending.clear();
      _scanFrom = 0;
    }
    return frames;
  }

  Uint8List? _extractOne() {
    final soi = _findMarker(0xD8, 0);
    if (soi < 0) {
      // No frame start yet: drop inter-frame garbage, but keep a trailing
      // 0xFF that might be half of a marker split across chunks.
      if (_pending.length > 1) {
        final tail = _pending.last;
        _pending.clear();
        if (tail == 0xFF) _pending.add(0xFF);
      }
      _scanFrom = 0;
      return null;
    }
    if (soi > 0) {
      _pending.removeRange(0, soi);
      _scanFrom = 0;
    }
    final eoi = _findMarker(0xD9, _scanFrom < 2 ? 2 : _scanFrom);
    if (eoi < 0) {
      // Resume next time just before the end (marker could split chunks).
      _scanFrom = _pending.length > 2 ? _pending.length - 1 : 2;
      return null;
    }
    final frame = Uint8List.fromList(_pending.sublist(0, eoi + 2));
    _pending.removeRange(0, eoi + 2);
    _scanFrom = 0;
    return frame;
  }

  int _findMarker(int second, int from) {
    for (var i = from; i + 1 < _pending.length; i++) {
      if (_pending[i] == 0xFF && _pending[i + 1] == second) return i;
    }
    return -1;
  }
}

/// Connects to an MJPEG URL and emits decoded-frame bytes until cancelled.
class NetworkCameraClient {
  NetworkCameraClient({http.Client Function()? clientFactory})
      : _makeClient = clientFactory ?? http.Client.new;

  final http.Client Function() _makeClient;

  /// JPEG frames from [url]. Cancel the subscription to disconnect; server
  /// errors and disconnects surface as stream errors / stream close.
  Stream<Uint8List> frames(Uri url) {
    late StreamController<Uint8List> controller;
    http.Client? client;
    StreamSubscription<List<int>>? sub;

    Future<void> start() async {
      client = _makeClient();
      try {
        final response = await client!.send(http.Request('GET', url));
        if (response.statusCode != 200) {
          throw NetworkCameraException(
              'Camera stream returned HTTP ${response.statusCode}');
        }
        final parser = MjpegFrameParser();
        sub = response.stream.listen(
          (chunk) {
            for (final frame in parser.add(chunk)) {
              if (!controller.isClosed) controller.add(frame);
            }
          },
          onError: (Object e, StackTrace st) {
            if (!controller.isClosed) {
              controller.addError(e, st);
              controller.close();
            }
          },
          onDone: () {
            if (!controller.isClosed) controller.close();
          },
          cancelOnError: true,
        );
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e is NetworkCameraException
              ? e
              : NetworkCameraException('Could not reach the camera: $e'));
          await controller.close();
        }
      }
    }

    controller = StreamController<Uint8List>(
      onListen: start,
      onCancel: () async {
        await sub?.cancel();
        client?.close();
      },
    );
    return controller.stream;
  }
}
