/// On-device OCR via Google ML Kit (bundled Latin model — works offline,
/// including on the Android emulator). The ONLY file that imports the ML Kit
/// plugin, mirroring how cloud_vision_recognizer.dart is the only file that
/// touches the network.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import 'battle_ocr.dart';

class MlkitTextOcr implements TextOcr {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<List<OcrLine>> readLines(Uint8List imageBytes) async {
    // ML Kit wants a file or a raw-format buffer; a temp JPEG file is the
    // simplest reliable path on both platforms.
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return const [];
    final w = decoded.width.toDouble(), h = decoded.height.toDouble();
    final tmp = File(
        '${Directory.systemTemp.path}/psa_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg');
    try {
      await tmp.writeAsBytes(img.encodeJpg(decoded, quality: 90));
      final result =
          await _recognizer.processImage(InputImage.fromFilePath(tmp.path));
      final lines = <OcrLine>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final box = line.boundingBox;
          lines.add(OcrLine(
            line.text,
            cx: ((box.left + box.right) / 2 / w).clamp(0.0, 1.0),
            cy: ((box.top + box.bottom) / 2 / h).clamp(0.0, 1.0),
            w: ((box.right - box.left) / w).clamp(0.0, 1.0),
            h: ((box.bottom - box.top) / h).clamp(0.0, 1.0),
          ));
        }
      }
      return lines;
    } finally {
      if (tmp.existsSync()) {
        try {
          tmp.deleteSync();
        } catch (_) {}
      }
    }
  }

  void dispose() => _recognizer.close();
}
