/// Cloud vision recognition via the Anthropic Messages API. The ONLY file
/// in lib/ that talks to the network. Prompt/JSON contract documented in
/// docs/RECOGNITION_PROMPT.md — keep the two in sync.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../data/data_pack.dart';
import '../models/recognition_result.dart';
import 'recognition_service.dart';

class CloudVisionRecognizer implements RecognitionService {
  final DataPack pack;
  final String apiKey;
  final String model;
  final http.Client _client;
  final Uri _endpoint;

  CloudVisionRecognizer(
    this.pack, {
    required this.apiKey,
    this.model = 'claude-sonnet-4-5',
    http.Client? client,
    Uri? endpoint,
  })  : _client = client ?? http.Client(),
        _endpoint = endpoint ?? Uri.parse('https://api.anthropic.com/v1/messages');

  @override
  String get name => 'cloud-vision';

  @override
  Future<RecognitionResult> recognize(
    Uint8List imageBytes, {
    required BattleSnapshotContext context,
  }) async {
    if (apiKey.isEmpty) {
      throw const RecognitionException(
          'No API key configured — add one in Settings, or use manual entry.');
    }
    if (imageBytes.isEmpty) {
      throw const RecognitionException('Empty image.');
    }

    final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint,
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode(_requestBody(imageBytes, context)),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw RecognitionException('Network error: $e');
    }

    if (response.statusCode != 200) {
      throw RecognitionException(
          'API error ${response.statusCode}: ${response.body}');
    }

    return _parseResponse(response.body);
  }

  Map<String, dynamic> _requestBody(
      Uint8List imageBytes, BattleSnapshotContext context) {
    final roster = pack.species.values.map((s) => s.name).join(', ');
    final yourNames =
        context.yourSpeciesIds.map(pack.speciesName).join(', ');
    final prompt = '''
This is a photo or screenshot of a Pokemon Champions battle screen.
My own Pokemon (bottom/near side) are among: $yourNames.
Identify every Pokemon visible on the battle field (up to ${context.enemyFieldSlots} per side).

Match enemy Pokemon against this roster (on-screen names may be nicknames — identify by the 3D model first, name text second): $roster.

Reply with ONLY a JSON object, no other text:
{"pokemon":[{"name":"<species name from the roster>","side":"yours"|"enemy","hpPercent":<0-100 or null>,"mega":<true|false>,"confidence":<0.0-1.0>}]}''';

    return {
      'model': model,
      'max_tokens': 1024,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': 'image/jpeg',
                'data': base64Encode(imageBytes),
              },
            },
            {'type': 'text', 'text': prompt},
          ],
        }
      ],
    };
  }

  RecognitionResult _parseResponse(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final content = (decoded['content'] as List?) ?? const [];
    final text = content
        .whereType<Map<String, dynamic>>()
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join('\n');

    // Tolerate a model that wraps JSON in prose or code fences.
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (match == null) {
      throw RecognitionException('No JSON in model response: $text');
    }

    final Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(match.group(0)!) as Map<String, dynamic>;
    } catch (e) {
      throw RecognitionException('Bad JSON from model: $e');
    }

    final slots = <RecognizedPokemon>[];
    for (final raw in (parsed['pokemon'] as List?) ?? const []) {
      final p = raw as Map<String, dynamic>;
      final speciesId = pack.resolveSpeciesName((p['name'] as String?) ?? '');
      if (speciesId == null) continue; // unknown to current pack — skip
      slots.add(RecognizedPokemon(
        speciesId: speciesId,
        side: (p['side'] as String?) == 'yours'
            ? BattleSide.yours
            : BattleSide.enemy,
        confidence: ((p['confidence'] as num?) ?? 0.5).toDouble(),
        hpPercent: (p['hpPercent'] as num?)?.toInt(),
        isMega: (p['mega'] as bool?) ?? false,
      ));
    }

    if (slots.isEmpty) {
      throw const RecognitionException(
          'The model found no recognizable Pokemon in the image.');
    }
    return RecognitionResult(slots: slots, engine: name);
  }
}
