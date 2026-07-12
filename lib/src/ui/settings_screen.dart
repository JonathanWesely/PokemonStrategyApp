/// Settings: recognition engine, API key, data pack info.
library;

import 'package:flutter/material.dart';

import '../app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  TextEditingController? _apiKeyControllerInternal;

  TextEditingController get _apiKeyController =>
      _apiKeyControllerInternal ??=
          TextEditingController(text: AppScope.of(context).apiKey);

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
                  value: 'mock',
                  title: Text('Mock (no camera, no API key)'),
                  subtitle: Text(
                      'Simulates recognition with plausible enemies — for testing',
                      style: TextStyle(fontSize: 11)),
                ),
                RadioListTile<String>(
                  value: 'cloud-vision',
                  title: Text('Cloud vision (Anthropic API)'),
                  subtitle: Text(
                      'Reads real battle photos — needs the API key below',
                      style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Anthropic API key',
              helperText: 'Stored only on this device',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.save),
                onPressed: () async {
                  await state.updateSettings(
                      newApiKey: _apiKeyController.text.trim());
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('API key saved')));
                  }
                },
              ),
            ),
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
                      'Items: ${state.pack.items.length}'),
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
