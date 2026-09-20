/// Diagnostic: dump what the matcher saw for the fixture photo and the
/// synthetic preview screen — panel rects, badge reads, segmented crops and
/// the top-8 per panel — into `test/_scan_dump/`. Not a real test (it never
/// fails); run it on its own:
///
///   flutter test test/scan_dump_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pokemon_strategy_app/src/recognition/sprite_matcher.dart';

import 'helpers.dart';

Future<Uint8List?> fileLoader(String path) async {
  final f = File(path);
  return f.existsSync() ? f.readAsBytesSync() : null;
}

/// Same composition as sprite_matcher_test.dart.
Uint8List composePreview(List<String> speciesIds) {
  const w = 1200, h = 900;
  final canvas = img.Image(width: w, height: h);
  img.fill(canvas, color: img.ColorRgb8(40, 90, 60));
  const panelX = 780, panelW = 330;
  const panelH = 90, gap = 28, startY = 110;
  for (var i = 0; i < speciesIds.length; i++) {
    final y0 = startY + i * (panelH + gap);
    img.fillRect(canvas,
        x1: panelX,
        y1: y0,
        x2: panelX + panelW,
        y2: y0 + panelH,
        color: img.ColorRgb8(216, 44, 100));
    final champions = File('test/fixtures/champions/${speciesIds[i]}.png');
    final spriteBytes = champions.existsSync()
        ? champions.readAsBytesSync()
        : File('assets/sprites/home/${speciesIds[i]}.png').readAsBytesSync();
    final sprite = img.decodeImage(spriteBytes)!;
    final scaled = img.copyResize(sprite, height: panelH - 10);
    img.compositeImage(canvas, scaled,
        dstX: panelX + (panelW * 0.22).round(), dstY: y0 + 5);
  }
  return Uint8List.fromList(img.encodeJpg(canvas, quality: 90));
}

void Function(SpriteMatchDebug) writerFor(String name) {
  final dir = Directory('test/_scan_dump/$name');
  return (report) {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    File('${dir.path}/frame.jpg').writeAsBytesSync(report.frameJpeg);
    for (var i = 0; i < report.crops.length; i++) {
      File('${dir.path}/panel_${i + 1}.png').writeAsBytesSync(report.crops[i]);
    }
    final frame = img.decodeImage(report.frameJpeg);
    if (frame != null) {
      final k = frame.width > 1600 ? 1600 / frame.width : 1.0;
      final canvas = k < 1.0
          ? img.copyResize(frame, width: (frame.width * k).round())
          : frame;
      for (var i = 0; i < report.panels.length; i++) {
        final r = report.panels[i];
        final x0 = (r[0] * k).round(), y0 = (r[1] * k).round();
        final x1 = (r[2] * k).round(), y1 = (r[3] * k).round();
        final pw = x1 - x0;
        img.drawRect(canvas,
            x1: x0, y1: y0, x2: x1, y2: y1,
            color: img.ColorRgb8(0, 255, 0), thickness: 2);
        img.drawRect(canvas,
            x1: x0 + (pw * 0.14).round(), y1: y0,
            x2: x0 + (pw * 0.62).round(), y2: y1,
            color: img.ColorRgb8(0, 255, 255), thickness: 1);
        // Yellow = this badge box yielded a type, magenta = it read nothing.
        final List<List<int>> boxes = i < report.badgeBoxes.length
            ? report.badgeBoxes[i]
            : const <List<int>>[];
        for (final b in boxes) {
          img.drawRect(canvas,
              x1: (b[0] * k).round(),
              y1: (b[1] * k).round(),
              x2: (b[2] * k).round(),
              y2: (b[3] * k).round(),
              color: b.length > 4 && b[4] == 1
                  ? img.ColorRgb8(255, 230, 0)
                  : img.ColorRgb8(255, 0, 255),
              thickness: 1);
        }
      }
      File('${dir.path}/overlay.jpg')
          .writeAsBytesSync(img.encodeJpg(canvas, quality: 85));
    }
    final lines = <String>[
      'frame ${report.frameWidth}x${report.frameHeight}  '
          'detect@${report.workWidth}  scale ${report.scale.toStringAsFixed(2)}',
    ];
    for (var i = 0; i < report.panels.length; i++) {
      final r = report.panels[i];
      final types =
          report.panelTypes[i].isEmpty ? '-' : report.panelTypes[i].join('+');
      final top = report.ranked[i]
          .map((c) => '${c.$1}:${c.$2.toStringAsFixed(3)}[${c.$3[0]}]')
          .join('  ');
      final got = i < report.assigned.length ? report.assigned[i] : '?';
      lines.add('panel ${i + 1} rect ${r[0]},${r[1]},${r[2]},${r[3]} '
          '(${r[2] - r[0]}x${r[3] - r[1]}) types[$types] -> $got\n    $top');
    }
    final text = lines.join('\n');
    File('${dir.path}/report.txt').writeAsStringSync(text);
    // ignore: avoid_print
    print('--- $name\n$text');
  };
}

void main() {
  final pack = loadRealDataPack();

  test('dump select1 + synthetic scans', () async {
    for (final (name, bytes) in <(String, Uint8List?)>[
      (
        'select1',
        File('test/fixtures/select1.jpeg').existsSync()
            ? File('test/fixtures/select1.jpeg').readAsBytesSync()
            : null
      ),
      (
        'preview1',
        File('test/fixtures/preview1.jpeg').existsSync()
            ? File('test/fixtures/preview1.jpeg').readAsBytesSync()
            : null
      ),
      (
        'synthetic',
        composePreview(const [
          'garchomp',
          'dragonite',
          'gholdengo',
          'pelipper',
          'torkoal',
          'metagross'
        ])
      ),
    ]) {
      if (bytes == null) continue;
      final matcher = SpriteMatcher(
        pack,
        loadBytes: fileLoader,
        exemplars: ExemplarStore(loadBundled: (_) async => null),
        onDebug: writerFor(name),
      );
      final matches = await matcher.matchPreview(bytes);
      // ignore: avoid_print
      print('$name assigned: ${[for (final m in matches) m.assigned.speciesId]}');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
