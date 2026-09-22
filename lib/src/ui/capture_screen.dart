/// Camera capture + gallery import + network-rig streaming for snapshots —
/// the ONLY file that imports the camera / image_picker plugins. (Network
/// bytes come from `recognition/network_camera.dart`, per the isolation
/// rule in CLAUDE.md.)
///
/// Three sources, one scan path:
///   * Phone camera — point the phone at the Switch (or the emulator's
///     Webcam0 at your laptop camera).
///   * Gallery — import a screenshot / photo.
///   * Rig — the clamp-on/TV-stand camera pod streaming MJPEG at
///     `http://<ip>:81/stream` (also works with any MJPEG source, e.g. the
///     IP Webcam Android app, for testing without the rig).
///
/// Two modes, matching the two battle tabs:
///   * Team Preview scan — fills the enemy roster boxes.
///   * Battle scan — updates who is on the field.
///
/// "Auto" re-scans every few seconds for hands-free tracking in either
/// source.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../models/recognition_result.dart';
import '../recognition/network_camera.dart';
import '../recognition/recognition_service.dart';

/// Sharpness of a JPEG frame: variance of the Laplacian over the centre
/// half of the image, downscaled so the number is comparable across stream
/// resolutions. Runs in an isolate via [compute]; pure Dart, no plugins.
double focusScoreOf(Uint8List jpeg) {
  final im = img.decodeImage(jpeg);
  if (im == null) return 0;
  var c = img.copyCrop(im,
      x: im.width ~/ 4,
      y: im.height ~/ 4,
      width: im.width ~/ 2,
      height: im.height ~/ 2);
  if (c.width > 480) c = img.copyResize(c, width: 480);
  final g = img.grayscale(c);
  final w = g.width, h = g.height;
  final lum = Float64List(w * h);
  var i = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++, i++) {
      lum[i] = g.getPixel(x, y).r.toDouble();
    }
  }
  var sum = 0.0, sum2 = 0.0, n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final k = y * w + x;
      final lap = 4 * lum[k] - lum[k - 1] - lum[k + 1] - lum[k - w] - lum[k + w];
      sum += lap;
      sum2 += lap * lap;
      n++;
    }
  }
  if (n == 0) return 0;
  final mean = sum / n;
  return sum2 / n - mean * mean;
}

/// Pick an image from the gallery and return its bytes (null = cancelled).
/// Lives here because of the plugin-isolation rule: image_picker is only
/// imported by this file.
Future<Uint8List?> pickGalleryImageBytes() async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  return picked.readAsBytes();
}

class CaptureScreen extends StatefulWidget {
  final RecognitionScreen mode;

  /// Photo mode: instead of scanning, "Snap" pops this route with the raw
  /// JPEG bytes (Scan Team uses it to collect the two display images). The
  /// rig is preselected when an address is saved — same default as
  /// auto-scan.
  final bool returnPhoto;
  final String? photoTitle;

  const CaptureScreen(
      {super.key, required this.mode, this.returnPhoto = false, this.photoTitle});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? _camera;
  String? _cameraError;
  bool _busy = false;
  bool _auto = false;
  Timer? _autoTimer;
  String _status = '';

  // Network rig source.
  bool _netMode = false;
  final NetworkCameraClient _netClient = NetworkCameraClient();
  StreamSubscription<Uint8List>? _netSub;
  Uint8List? _netFrame;

  /// Live sharpness of the rig stream (Laplacian variance of the frame
  /// centre), refreshed about once a second off the UI isolate. Higher is
  /// sharper; the number only means anything relative to itself — turn the
  /// lens until it peaks. The first rig frame scored ~30 where a usable
  /// phone photo of the same screen scores 400+.
  double? _focus;
  int _lastFocusMs = 0;
  bool _focusBusy = false;
  String? _netError;
  TextEditingController? _urlCtrl;
  int _lastFramePaintMs = 0;

  /// Auto-scan is paused while this screen is open: the rig's ESP32 serves
  /// ONE stream client at a time, so the manual view must own it. If the
  /// user had paused it THEMSELVES, closing this screen keeps it paused.
  AppState? _appState;
  bool _autoScanWasPaused = false;

  static const autoInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    _urlCtrl ??= TextEditingController(text: state.netCamUrl);
    if (_appState == null) {
      _appState = state;
      _autoScanWasPaused = state.autoScan?.isPaused ?? false;
      state.autoScan?.pause('paused while the manual camera view is open');
      // Photo mode defaults to the rig, like every other capture path.
      if (widget.returnPhoto && state.netCamUrl.trim().isNotEmpty) {
        _netMode = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_connected) _connectNet();
        });
      }
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError =
            'No camera found — use the gallery button to import a screenshot.');
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      // 1080p, not 720p: the enemy sprites are ~4% of the frame height, and
      // at 720p that is a 25-px creature. The matcher's references are 32 px.
      final controller = CameraController(back, ResolutionPreset.veryHigh,
          enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (e) {
      if (mounted) {
        setState(() => _cameraError =
            'Camera unavailable ($e) — use the gallery button instead.');
      }
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _netSub?.cancel();
    _urlCtrl?.dispose();
    _camera?.dispose();
    if (!_autoScanWasPaused) _appState?.autoScan?.resume();
    super.dispose();
  }

  Future<void> _recognize(Uint8List bytes) async {
    if (widget.returnPhoto) {
      if (mounted) Navigator.pop(context, bytes);
      return;
    }
    final state = AppScope.of(context);
    setState(() {
      _busy = true;
      _status = 'Recognizing…';
    });
    try {
      final result = await state.runSnapshot(bytes, screen: widget.mode);
      if (!mounted) return;
      final enemies = result.enemies.length;
      setState(() => _status = widget.mode == RecognitionScreen.preview
          ? 'Found $enemies enemy Pokemon — check the boxes, tap any to fix'
          : 'Updated the field ($enemies enemy on-field)');
      if (!_auto && widget.mode == RecognitionScreen.preview) {
        // One-shot preview scan: hop back so the user sees the boxes.
        Navigator.pop(context);
      }
    } on RecognitionException catch (e) {
      if (mounted) setState(() => _status = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shoot() async {
    if (_busy) return;
    if (_netMode) {
      final frame = _netFrame;
      if (frame != null) await _recognize(frame);
      return;
    }
    final camera = _camera;
    if (camera == null) return;
    try {
      final file = await camera.takePicture();
      await _recognize(await file.readAsBytes());
    } catch (e) {
      if (mounted) setState(() => _status = 'Capture failed: $e');
    }
  }

  Future<void> _importFromGallery() async {
    if (_busy) return;
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    await _recognize(await picked.readAsBytes());
  }

  void _toggleAuto(bool on) {
    setState(() => _auto = on);
    _autoTimer?.cancel();
    if (on) {
      _autoTimer = Timer.periodic(autoInterval, (_) {
        if (!_busy) _shoot();
      });
    }
  }

  // ------------------------------------------------------- network rig --

  bool get _connected => _netSub != null && _netError == null;

  void _connectNet() {
    final text = _urlCtrl?.text ?? '';
    final url = normalizeStreamUrl(text);
    if (url == null) {
      setState(() => _netError =
          'Enter the rig address, e.g. 192.168.4.2 or http://ip:81/stream');
      return;
    }
    // Remember it for next time (and across pod/dock swaps).
    AppScope.of(context).updateSettings(newNetCamUrl: text.trim());
    _netSub?.cancel();
    setState(() {
      _netError = null;
      _netFrame = null;
      _status = 'Connecting to $url…';
    });
    _netSub = _netClient.frames(url).listen(
      (frame) {
        if (!mounted) return;
        // Cap preview repaints at ~15 fps; scans always use the newest frame.
        final now = DateTime.now().millisecondsSinceEpoch;
        _netFrame = frame;
        if (now - _lastFramePaintMs > 66) {
          _lastFramePaintMs = now;
          setState(() {
            if (_status.startsWith('Connecting')) _status = '';
          });
        }
        if (!_focusBusy && now - _lastFocusMs > 1000) {
          _focusBusy = true;
          _lastFocusMs = now;
          compute(focusScoreOf, frame).then((score) {
            if (!mounted) return;
            setState(() {
              _focus = score;
              _focusBusy = false;
            });
          }).catchError((Object _) {
            _focusBusy = false;
          });
        }
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _netError = '$e';
          _netSub = null;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          _netError ??= 'Stream ended — is the rig still powered?';
          _netSub = null;
        });
      },
    );
  }

  void _disconnectNet() {
    _netSub?.cancel();
    setState(() {
      _netSub = null;
      _netError = null;
      _status = '';
    });
  }

  Widget _buildNetPane() {
    final frame = _netFrame;
    if (_connected && frame != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(frame, fit: BoxFit.contain, gaplessPlayback: true),
          Positioned(
            top: 8,
            right: 8,
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.link_off, size: 16),
              label: const Text('Disconnect'),
              onPressed: _disconnectNet,
            ),
          ),
          if (_focus != null)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Focus ${_focus!.toStringAsFixed(0)}  '
                  '${_focus! < 120 ? "— turn the lens" : _focus! < 300 ? "— getting there" : "— sharp"}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_tethering, size: 40),
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Rig stream address',
                hintText: '192.168.4.2  (or http://ip:81/stream)',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _connectNet(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: Icon(_connected ? Icons.sync : Icons.link),
              label: Text(_connected ? 'Waiting for frames…' : 'Connect'),
              onPressed: _connected ? null : _connectNet,
            ),
            if (_netError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _netError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                'The rig streams at http://<its-ip>:81/stream once it joins '
                'your hotspot (IP shown in its serial log). Any MJPEG source '
                'works — e.g. the IP Webcam app at http://<phone-ip>:8080/video.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final title = widget.photoTitle ??
        (widget.mode == RecognitionScreen.preview
            ? 'Scan team preview'
            : 'Scan battle');
    final canSnap = !_busy &&
        (_netMode ? (_connected && _netFrame != null) : camera != null);
    final canAuto =
        !widget.returnPhoto && (_netMode ? _connected : camera != null);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              segments: const [
                ButtonSegment(
                    value: false,
                    icon: Icon(Icons.photo_camera_outlined, size: 18),
                    tooltip: 'Phone camera'),
                ButtonSegment(
                    value: true,
                    icon: Icon(Icons.wifi_tethering, size: 18),
                    tooltip: 'Camera rig (network stream)'),
              ],
              selected: {_netMode},
              onSelectionChanged: (sel) =>
                  setState(() => _netMode = sel.first),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _netMode
                ? _buildNetPane()
                : (camera != null
                    ? CameraPreview(camera)
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _cameraError ?? 'Starting camera…',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      )),
          ),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(_status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12)),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton.outlined(
                    tooltip: 'Import from gallery',
                    icon: const Icon(Icons.photo_library_outlined),
                    onPressed: _busy ? null : _importFromGallery,
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.photo_camera),
                    label: Text(_busy ? 'Working…' : 'Snap'),
                    onPressed: canSnap ? _shoot : null,
                  ),
                  const Spacer(),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: _auto,
                        onChanged: canAuto ? (v) => _toggleAuto(v) : null,
                      ),
                      const Text('Auto', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
