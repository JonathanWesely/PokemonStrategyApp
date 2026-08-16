/// Camera capture + gallery import for snapshots — the ONLY file that
/// imports the camera / image_picker plugins.
///
/// Two modes, matching the two battle tabs:
///   * Team Preview scan — point at the team-select screen (or import a
///     screenshot); fills the enemy roster boxes.
///   * Battle scan — point at the battle screen; updates who is on the field.
///
/// "Auto" re-scans every few seconds for hands-mostly-free tracking (the
/// plan's live mode, v1). On the Android emulator, set the AVD's back camera
/// to "Webcam0" and point your laptop camera at the Switch — or use the
/// gallery button with a photo dragged onto the emulator.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../models/recognition_result.dart';
import '../recognition/recognition_service.dart';

class CaptureScreen extends StatefulWidget {
  final RecognitionScreen mode;

  const CaptureScreen({super.key, required this.mode});

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

  static const autoInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _initCamera();
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
      final controller = CameraController(back, ResolutionPreset.high,
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
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _recognize(Uint8List bytes) async {
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
    final camera = _camera;
    if (camera == null || _busy) return;
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

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final title = widget.mode == RecognitionScreen.preview
        ? 'Scan team preview'
        : 'Scan battle';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: camera != null
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
                  ),
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
                    onPressed: (_busy || camera == null) ? null : _shoot,
                  ),
                  const Spacer(),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: _auto,
                        onChanged:
                            camera == null ? null : (v) => _toggleAuto(v),
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
