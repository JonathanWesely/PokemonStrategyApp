/// Recognition engines: the mock (fully offline) and the cloud recognizer's
/// request/parse logic against a fake HTTP transport (http's MockClient) —
/// the same "fake firmware" trick the golf app used for its BLE link.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pokemon_strategy_app/src/models/recognition_result.dart';
import 'package:pokemon_strategy_app/src/recognition/cloud_vision_recognizer.dart';
import 'package:pokemon_strategy_app/src/recognition/mock_recognizer.dart';
import 'package:pokemon_strategy_app/src/recognition/recognition_service.dart';

import 'helpers.dart';

void main() {
  final pack = loadRealDataPack();
  const context = BattleSnapshotContext(
    yourSpeciesIds: ['chien-pao', 'torkoal', 'amoonguss', 'farigiraf'],
    enemyFieldSlots: 2,
  );

  group('MockRecognizer', () {
    test('returns your leads plus distinct plausible enemies', () async {
      final result = await MockRecognizer(pack, seed: 42)
          .recognize(Uint8List(0), context: context);
      expect(result.engine, 'mock');
      expect(result.yours.length, 2);
      expect(result.yours.first.speciesId, 'chien-pao');
      expect(result.enemies.length, 2);
      expect(result.enemies.map((e) => e.speciesId).toSet().length, 2);
      for (final enemy in result.enemies) {
        expect(pack.species.containsKey(enemy.speciesId), isTrue);
      }
    });

    test('scripted enemies are returned verbatim', () async {
      final mock = MockRecognizer(pack,
          scriptedEnemies: ['incineroar', 'rillaboom']);
      final result = await mock.recognize(Uint8List(0), context: context);
      expect(result.enemies.map((e) => e.speciesId).toList(),
          ['incineroar', 'rillaboom']);
    });
  });

  group('CloudVisionRecognizer', () {
    http.Client fakeApi(Map<String, dynamic> reply,
        {int status = 200, void Function(http.Request)? onRequest}) {
      return MockClient((request) async {
        onRequest?.call(request);
        return http.Response(jsonEncode(reply), status,
            headers: {'content-type': 'application/json'});
      });
    }

    Map<String, dynamic> anthropicReply(String text) => {
          'content': [
            {'type': 'text', 'text': text}
          ],
        };

    test('parses a clean JSON reply into resolved species', () async {
      final reply = anthropicReply(jsonEncode({
        'pokemon': [
          {
            'name': 'Incineroar',
            'side': 'enemy',
            'hpPercent': 87,
            'mega': false,
            'confidence': 0.97
          },
          {
            'name': 'Rillaboom',
            'side': 'enemy',
            'hpPercent': null,
            'mega': false,
            'confidence': 0.91
          },
          {'name': 'Chien-Pao', 'side': 'yours', 'hpPercent': 100},
        ]
      }));

      http.Request? seen;
      final recognizer = CloudVisionRecognizer(
        pack,
        apiKey: 'sk-test',
        client: fakeApi(reply, onRequest: (r) => seen = r),
      );
      final result = await recognizer.recognize(
        Uint8List.fromList([1, 2, 3]),
        context: context,
      );

      expect(result.engine, 'cloud-vision');
      expect(result.enemies.length, 2);
      expect(result.enemies.first.speciesId, 'incineroar');
      expect(result.enemies.first.hpPercent, 87);
      expect(result.yours.single.speciesId, 'chien-pao');

      // Request sanity: right headers, image attached.
      expect(seen!.headers['x-api-key'], 'sk-test');
      final body = jsonDecode(seen!.body) as Map<String, dynamic>;
      final content =
          ((body['messages'] as List).first as Map)['content'] as List;
      expect((content.first as Map)['type'], 'image');
    });

    test('tolerates prose/code-fence wrapping around the JSON', () async {
      final reply = anthropicReply('Here you go:\n```json\n'
          '{"pokemon":[{"name":"Gengar","side":"enemy","mega":true,'
          '"confidence":0.9,"hpPercent":55}]}\n```');
      final recognizer =
          CloudVisionRecognizer(pack, apiKey: 'k', client: fakeApi(reply));
      final result =
          await recognizer.recognize(Uint8List.fromList([1]), context: context);
      expect(result.enemies.single.speciesId, 'gengar');
      expect(result.enemies.single.isMega, isTrue);
    });

    test('unknown species names are skipped, not crashed on', () async {
      final reply = anthropicReply(jsonEncode({
        'pokemon': [
          {'name': 'MissingNo', 'side': 'enemy'},
          {'name': 'Torkoal', 'side': 'enemy'},
        ]
      }));
      final recognizer =
          CloudVisionRecognizer(pack, apiKey: 'k', client: fakeApi(reply));
      final result =
          await recognizer.recognize(Uint8List.fromList([1]), context: context);
      expect(result.enemies.single.speciesId, 'torkoal');
    });

    test('missing API key / empty image / API error all throw cleanly',
        () async {
      final noKey = CloudVisionRecognizer(pack,
          apiKey: '', client: fakeApi(anthropicReply('{}')));
      expect(
        () => noKey.recognize(Uint8List.fromList([1]), context: context),
        throwsA(isA<RecognitionException>()),
      );

      final withKey = CloudVisionRecognizer(pack,
          apiKey: 'k', client: fakeApi(anthropicReply('{}')));
      expect(
        () => withKey.recognize(Uint8List(0), context: context),
        throwsA(isA<RecognitionException>()),
      );

      final apiError = CloudVisionRecognizer(pack,
          apiKey: 'k',
          client: fakeApi({'error': 'overloaded'}, status: 529));
      expect(
        () => apiError.recognize(Uint8List.fromList([1]), context: context),
        throwsA(isA<RecognitionException>()),
      );
    });
  });
}
