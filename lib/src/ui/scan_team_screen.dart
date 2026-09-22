/// Scan Team: collect the two Champions team-display images ("Moves &
/// More", then "Stats"), run [TeamScanner], and hand the result back to the
/// team editor. Each image can be uploaded from the gallery or taken live —
/// the camera view defaults to the rig stream, same as every other capture
/// path.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../recognition/recognition_service.dart';
import '../recognition/team_scanner.dart';
import 'capture_screen.dart';

class ScanTeamScreen extends StatefulWidget {
  const ScanTeamScreen({super.key});

  @override
  State<ScanTeamScreen> createState() => _ScanTeamScreenState();
}

class _ScanTeamScreenState extends State<ScanTeamScreen> {
  Uint8List? _movesImage;
  Uint8List? _statsImage;
  bool _busy = false;
  String? _error;

  Future<void> _pick(bool movesStep, {required bool fromCamera}) async {
    setState(() => _error = null);
    Uint8List? bytes;
    if (fromCamera) {
      bytes = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (_) => CaptureScreen(
            mode: RecognitionScreen.preview,
            returnPhoto: true,
            photoTitle: movesStep
                ? 'Photo 1 · Moves & More'
                : 'Photo 2 · Stats',
          ),
        ),
      );
    } else {
      bytes = await pickGalleryImageBytes();
    }
    if (bytes == null || !mounted) return;
    setState(() {
      if (movesStep) {
        _movesImage = bytes;
      } else {
        _statsImage = bytes;
      }
    });
    if (_movesImage != null && _statsImage != null) await _analyze();
  }

  Future<void> _analyze() async {
    final state = AppScope.of(context);
    final ocr = state.ocr;
    if (ocr == null) {
      setState(() => _error =
          'On-device text recognition is not available here — Scan Team '
          'needs it.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final scanner = TeamScanner(state.pack, loadBytes: state.assetLoader);
      final result = await scanner.scan(
        movesImage: _movesImage!,
        statsImage: _statsImage!,
        ocr: ocr,
      );
      if (!mounted) return;
      if (result.slots.isEmpty) {
        setState(() {
          _busy = false;
          _error = result.warnings.isEmpty
              ? 'Could not read a team from these images.'
              : result.warnings.join('\n');
        });
        return;
      }
      Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Scan failed: $e';
        });
      }
    }
  }

  Widget _step({
    required int number,
    required String title,
    required String hint,
    required Uint8List? image,
    required bool movesStep,
    required bool enabled,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor:
                      image != null ? Colors.green : Colors.blueGrey,
                  child: image != null
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text('$number',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(hint,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            if (image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(image, height: 110, fit: BoxFit.cover),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: Text(image == null ? 'Upload image' : 'Replace'),
                    onPressed: enabled && !_busy
                        ? () => _pick(movesStep, fromCamera: false)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.photo_camera, size: 18),
                    label: const Text('Take picture'),
                    onPressed: enabled && !_busy
                        ? () => _pick(movesStep, fromCamera: true)
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan team')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            'Open your team in Pokemon Champions and capture both pages of '
            'the team display. Names, moves, abilities, items, stats, '
            'natures and genders are read for you — anything uncertain gets '
            'flagged for review in the editor.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          _step(
            number: 1,
            title: 'Moves & More page',
            hint: 'The page with abilities, held items and the four moves.',
            image: _movesImage,
            movesStep: true,
            enabled: true,
          ),
          _step(
            number: 2,
            title: 'Stats page',
            hint: 'Press R in-game for the page with the six stat rows.',
            image: _statsImage,
            movesStep: false,
            enabled: _movesImage != null,
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 8),
                  Text('Reading the team… this can take a few seconds.',
                      style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          if (!_busy && _movesImage != null && _statsImage != null)
            FilledButton.icon(
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Analyze again'),
              onPressed: _analyze,
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.error)),
            ),
        ],
      ),
    );
  }
}
