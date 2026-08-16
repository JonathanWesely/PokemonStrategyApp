/// Settings: recognition engine (Local / API / Mock), API provider config,
/// data pack info.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  TextEditingController? _apiKey;
  TextEditingController? _baseUrl;
  TextEditingController? _model;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    _apiKey ??= TextEditingController(text: state.apiKey);
    _baseUrl ??= TextEditingController(text: state.apiBaseUrl);
    _model ??= TextEditingController(text: state.apiModel);
  }

  @override
  void dispose() {
    _apiKey?.dispose();
    _baseUrl?.dispose();
    _model?.dispose();
    super.dispose();
  }

  Future<void> _saveApiFields() async {
    final state = AppScope.of(context);
    await state.updateSettings(
      newApiKey: _apiKey!.text.trim(),
      newApiBaseUrl: _baseUrl!.text.trim(),
      newApiModel: _model!.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('API settings saved')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Recognition engine',
              style: Theme.of(context).textTheme.titleSmall),
          RadioGroup<String>(
            groupValue: state.engineName,
            onChanged: (value) => state.updateSettings(newEngine: value),
            child: const Column(
              children: [
                RadioListTile<String>(
                  value: 'local',
                  title: Text('Local / on-device (no cloud AI, no tokens)'),
                  subtitle: Text(
                      'Sprite matching for the team-preview screen + OCR for '
                      'the battle screen, fully offline. Learns from every '
                      'photo you confirm — expect a few corrections in your '
                      'first battles.',
                      style: TextStyle(fontSize: 11)),
                ),
                RadioListTile<String>(
                  value: 'api',
                  title: Text('AI API (plug in any vision model)'),
                  subtitle: Text(
                      'Anthropic, or any OpenAI-compatible endpoint (OpenAI, '
                      'Gemini, local Ollama/LM Studio). Most accurate; needs '
                      'the settings below.',
                      style: TextStyle(fontSize: 11)),
                ),
                RadioListTile<String>(
                  value: 'mock',
                  title: Text('Mock (no camera, no key — for testing)'),
                  subtitle: Text(
                      'Simulates recognition with plausible enemies',
                      style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Text('API engine settings',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: state.apiProvider,
            decoration: const InputDecoration(
              labelText: 'Provider',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                  value: 'anthropic', child: Text('Anthropic (Claude)')),
              DropdownMenuItem(
                  value: 'openai',
                  child: Text('OpenAI-compatible (OpenAI / Gemini / Ollama…)')),
            ],
            onChanged: (v) {
              if (v != null) state.updateSettings(newApiProvider: v);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _model,
            decoration: InputDecoration(
              labelText: 'Model',
              hintText: state.apiProvider == 'openai'
                  ? 'e.g. gpt-4o, gemini-2.5-flash, llava'
                  : 'e.g. claude-sonnet-4-5',
              helperText: 'Leave empty for the default',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _baseUrl,
            decoration: InputDecoration(
              labelText: 'Base URL (optional)',
              hintText: state.apiProvider == 'openai'
                  ? 'e.g. http://192.168.1.20:11434/v1 for Ollama'
                  : 'default: https://api.anthropic.com',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _apiKey,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API key',
              helperText: 'Stored only on this device',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Save API settings'),
            onPressed: _saveApiFields,
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Data pack', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Text('Regulation: ${state.pack.usage.regulation}'),
                  Text('Generated: ${state.pack.usage.generatedAt}'),
                  Text('Source: ${state.pack.usage.source}'),
                  Text('Species: ${state.pack.species.length} · '
                      'Moves: ${state.pack.moves.length} · '
                      'Items: ${state.pack.items.length} · '
                      'Abilities: ${state.pack.abilities.length}'),
                  if (state.pack.usage.note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(state.pack.usage.note,
                        style: const TextStyle(
                            fontSize: 11, fontStyle: FontStyle.italic)),
                  ],
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh data'),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Refresh data'),
                        content: const Text(
                            'Data packs are rebuilt on your PC with:\n\n'
                            'dart run tool/update_data.dart\n\n'
                            'then rebuilt into the app. Over-the-air refresh '
                            'ships in a later phase (plan §5.1).'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('OK')),
                        ],
                      ),
                    ),
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
