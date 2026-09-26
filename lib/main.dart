/// Pokemon Strategy App — battle companion for Pokemon Champions.
///
/// Boot sequence mirrors the golf app: open the database, load the data
/// pack, restore state, run. The recognition engine defaults to Local
/// (on-device sprite matching + OCR, no cloud); switch to an AI API or the
/// mock in Settings.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'src/app_state.dart';
import 'src/data/asset_loader.dart';
import 'src/recognition/mlkit_ocr.dart';
import 'src/recognition/sprite_matcher.dart';
import 'src/storage/app_database.dart';
import 'src/ui/home_screen.dart';

Future<Uint8List?> _bundleLoader(String path) async {
  try {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    return null; // asset not bundled (e.g. species without an exemplar seed)
  }
}

/// Exemplar persistence: PNGs under `documents/exemplars/speciesId/`.
Future<ExemplarStore> _buildExemplarStore() async {
  final store = ExemplarStore(loadBundled: _bundleLoader);
  final docs = await getApplicationDocumentsDirectory();
  final root = Directory(p.join(docs.path, 'exemplars'));
  if (root.existsSync()) {
    for (final dir in root.listSync().whereType<Directory>()) {
      final speciesId = p.basename(dir.path);
      final pngs = <Uint8List>[
        for (final f in dir.listSync().whereType<File>())
          if (f.path.endsWith('.png')) f.readAsBytesSync(),
      ];
      if (pngs.isNotEmpty) store.seedRuntime(speciesId, pngs);
    }
  }
  store.onAdded = (speciesId, png) {
    final dir = Directory(p.join(root.path, speciesId));
    dir.createSync(recursive: true);
    File(p.join(dir.path,
            'ex_${DateTime.now().millisecondsSinceEpoch}.png'))
        .writeAsBytesSync(png);
  };
  store.onCleared = () {
    if (root.existsSync()) root.deleteSync(recursive: true);
  };
  return store;
}

/// Scan diagnostics: every local team-preview scan overwrites
/// `documents/last_scan/` with the frame, an overlay of where the matcher
/// looked, each segmented crop, and a report — and prints the report to the
/// console. Pull it with:
///   `adb shell run-as <applicationId> tar -cf - app_flutter/last_scan | tar -xf -`
void Function(SpriteMatchDebug) _scanDebugWriter(Directory docs) {
  final dir = Directory(p.join(docs.path, 'last_scan'));
  return (report) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      File(p.join(dir.path, 'frame.jpg')).writeAsBytesSync(report.frameJpeg);
      for (var i = 0; i < report.crops.length; i++) {
        File(p.join(dir.path, 'panel_${i + 1}.png'))
            .writeAsBytesSync(report.crops[i]);
      }
      // Overlay on a copy of the frame no wider than 1600 px: panel rects
      // (green), sprite region (cyan), classifier window (orange), and every
      // badge box the reader looked at — yellow if it yielded a type,
      // magenta if it read nothing.
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
          // Orange = the classifier's fixed window (windowX/windowY in
          // assets/models/sprite_cnn.json) — the sprite must sit inside it.
          final ph = y1 - y0;
          img.drawRect(canvas,
              x1: x0 + (pw * 0.10).round(), y1: y0 + (ph * 0.04).round(),
              x2: x0 + (pw * 0.63).round(), y2: y0 + (ph * 0.96).round(),
              color: img.ColorRgb8(255, 140, 0), thickness: 1);
          // Yellow = this box yielded a type, magenta = it read nothing.
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
        File(p.join(dir.path, 'overlay.jpg'))
            .writeAsBytesSync(img.encodeJpg(canvas, quality: 85));
      }
      final lines = <String>[
        'frame ${report.frameWidth}x${report.frameHeight}  '
            'detect@${report.workWidth}  scale ${report.scale.toStringAsFixed(2)}',
        'runtime exemplars: ${report.runtimeExemplars.isEmpty ? "none" : report.runtimeExemplars}',
      ];
      for (var i = 0; i < report.panels.length; i++) {
        final r = report.panels[i];
        final types = report.panelTypes[i].isEmpty
            ? '-'
            : report.panelTypes[i].join('+');
        final top = report.ranked[i]
            .take(5)
            .map((c) => '${c.$1}:${c.$2.toStringAsFixed(2)}[${c.$3[0]}]')
            .join('  ');
        final got = i < report.assigned.length ? report.assigned[i] : '?';
        lines.add('panel ${i + 1} ${r[2] - r[0]}x${r[3] - r[1]}px '
            '@(${r[0]},${r[1]}) types[$types] -> $got\n    $top');
      }
      lines.add('tiers: [c]nn classifier [e]xemplar [t]emplate [a]rt');
      final text = lines.join('\n');
      File(p.join(dir.path, 'report.txt')).writeAsStringSync(text);
      debugPrint('--- scan debug -> ${dir.path}\n$text');
    } catch (e) {
      debugPrint('scan debug write failed: $e');
    }
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dbDir = await getDatabasesPath();
  final db = await AppDatabase.open(
    databaseFactory,
    path: p.join(dbDir, 'pokemon_strategy.db'),
  );
  final pack = await loadDataPackFromAssets();
  final exemplars = await _buildExemplarStore();
  final docs = await getApplicationDocumentsDirectory();

  final state = AppState(
    pack: pack,
    db: db,
    assetLoader: _bundleLoader,
    exemplars: exemplars,
    ocr: MlkitTextOcr(),
    // Always constructed; AppState only invokes it when scan diagnostics
    // are enabled (debug builds default on; release = Settings toggle).
    matchDebug: _scanDebugWriter(docs),
  );
  await state.restore();

  runApp(PokemonStrategyApp(state: state));
}

class PokemonStrategyApp extends StatelessWidget {
  final AppState state;

  const PokemonStrategyApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Pokemon Strategy',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.redAccent),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
