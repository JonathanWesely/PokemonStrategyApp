/// API recognition engine — plug in any multimodal AI model. The ONLY file
/// in lib/ that talks to the network. Prompt/JSON contract documented in
/// docs/RECOGNITION_PROMPT.md — keep the two in sync.
///
/// Two wire formats are supported behind one class:
///  * [ApiProvider.anthropic] — the Anthropic Messages API.
///  * [ApiProvider.openAiCompatible] — any endpoint speaking the OpenAI
///    chat-completions schema: OpenAI itself, Google Gemini's compatibility
///    endpoint, or a local model server (Ollama / LM Studio) for zero-cost
///    self-hosted recognition.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../data/data_pack.dart';
import '../models/recognition_result.dart';
import 'recognition_service.dart';

enum ApiProvider { anthropic, openAiCompatible }

class ApiRecognizer implements RecognitionService {
  final DataPack pack;
  final ApiProvider provider;
  final String apiKey;
  final String model;
  final http.Client _client;
  final Uri _endpoint;

  ApiRecognizer(
    this.pack, {
    required this.apiKey,
    this.provider = ApiProvider.anthropic,
    String? model,
    String? baseUrl,
    http.Client? client,
  })  : model = model ??
            (provider == ApiProvider.anthropic ? 'claude-sonnet-4-5' : 'gpt-4o'),
        _client = client ?? http.Client(),
        _endpoint = _resolveEndpoint(provider, baseUrl);

  static Uri _resolveEndpoint(ApiProvider provider, String? baseUrl) {
    switch (provider) {
      case ApiProvider.anthropic:
        final base = (baseUrl == null || baseUrl.trim().isEmpty)
            ? 'https://api.anthropic.com'
            : baseUrl.trim();
        return Uri.parse('${_stripSlash(base)}/v1/messages');
      case ApiProvider.openAiCompatible:
        final base = (baseUrl == null || baseUrl.trim().isEmpty)
            ? 'https://api.openai.com/v1'
            : baseUrl.trim();
        return Uri.parse('${_stripSlash(base)}/chat/completions');
    }
  }

  static String _stripSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  @override
  String get name => 'api';

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
            headers: _headers(),
            body: jsonEncode(_requestBody(imageBytes, context)),
          )
          .timeout(const Duration(seconds: 45));
    } catch (e) {
      throw RecognitionException('Network error: $e');
    }

    if (response.statusCode != 200) {
      throw RecognitionException(
          'API error ${response.statusCode}: ${response.body}');
    }

    return _parseResponse(response.body);
  }

  Map<String, String> _headers() => switch (provider) {
        ApiProvider.anthropic => {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'content-type': 'application/json',
          },
        ApiProvider.openAiCompatible => {
            'authorization': 'Bearer $apiKey',
            'content-type': 'application/json',
          },
      };

  String _prompt(BattleSnapshotContext context) {
    final roster = pack.species.values.map((s) => s.name).join(', ');
    final yourNames = context.yourSpeciesIds.map(pack.speciesName).join(', ');
    final screenText = switch (context.screen) {
      RecognitionScreen.preview => '''
This is a photo of the Pokemon Champions TEAM-SELECT screen. The right-hand
column shows the ENEMY team: ${context.enemyTeamSize} panels, each with a small
2D sprite icon and NO name text — identify each enemy from its 2D sprite art
alone, top to bottom. My own team (with names) is on the left: $yourNames.
Report ONLY the enemy side, in top-to-bottom panel order.''',
      RecognitionScreen.battle => '''
This is a photo or screenshot of a Pokemon Champions battle screen.
My own Pokemon (bottom/near side) are among: $yourNames.
Identify every Pokemon visible on the battle field (up to ${context.enemyFieldSlots} per side).
On-screen names may be nicknames — identify by the 3D model first, name text second.''',
    };
    return '''
$screenText

Match Pokemon against this roster: $roster.

Reply with ONLY a JSON object, no other text:
{"pokemon":[{"name":"<species name from the roster>","side":"yours"|"enemy","hpPercent":<0-100 or null>,"mega":<true|false>,"confidence":<0.0-1.0>}]}''';
  }

  Map<String, dynamic> _requestBody(
      Uint8List imageBytes, BattleSnapshotContext context) {
    final prompt = _prompt(context);
    final b64 = base64Encode(imageBytes);
    switch (provider) {
      case ApiProvider.anthropic:
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
                    'data': b64,
                  },
                },
                {'type': 'text', 'text': prompt},
              ],
            }
          ],
        };
      case ApiProvider.openAiCompatible:
        return {
          'model': model,
          'max_tokens': 1024,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/jpeg;base64,$b64'},
                },
                {'type': 'text', 'text': prompt},
              ],
            }
          ],
        };
    }
  }

  String _extractText(Map<String, dynamic> decoded) {
    switch (provider) {
      case ApiProvider.anthropic:
        final content = (decoded['content'] as List?) ?? const [];
        return content
            .whereType<Map<String, dynamic>>()
            .where((b) => b['type'] == 'text')
            .map((b) => b['text'] as String)
            .join('\n');
      case ApiProvider.openAiCompatible:
        final choices = (decoded['choices'] as List?) ?? const [];
        if (choices.isEmpty) return '';
        final message =
            (choices.first as Map<String, dynamic>)['message'];
        final content = (message as Map<String, dynamic>?)?['content'];
        if (content is String) return content;
        if (content is List) {
          return content
              .whereType<Map<String, dynamic>>()
              .map((b) => (b['text'] as String?) ?? '')
              .join('\n');
        }
        return '';
    }
  }

  RecognitionResult _parseResponse(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final text = _extractText(decoded);

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
