/// Central app state: data pack, saved teams, settings, the active battle,
/// and the pluggable recognition engine.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'data/data_pack.dart';
import 'models/battle_state.dart';
import 'models/pokemon_build.dart';
import 'models/recognition_result.dart';
import 'models/regulation.dart';
import 'models/team.dart';
import 'recognition/cloud_vision_recognizer.dart';
import 'recognition/local_recognizer.dart';
import 'recognition/mock_recognizer.dart';
import 'recognition/recognition_service.dart';
import 'storage/app_database.dart';

const settingApiKey = 'anthropic_api_key';
const settingEngine = 'recognition_engine'; // 'mock' | 'cloud-vision' | 'local'

class AppState extends ChangeNotifier {
  final DataPack pack;
  final AppDatabase db;

  List<Team> teams = [];
  String apiKey = '';
  String engineName = 'mock';
  BattleSession? battle;

  late RecognitionService _recognizer;

  AppState({required this.pack, required this.db}) {
    _recognizer = MockRecognizer(pack);
  }

  RecognitionService get recognizer => _recognizer;

  /// Load persisted teams + settings. Call once at startup.
  Future<void> restore() async {
    teams = await db.loadTeams();
    apiKey = await db.getSetting(settingApiKey) ?? '';
    engineName = await db.getSetting(settingEngine) ?? 'mock';
    _rebuildRecognizer();
    notifyListeners();
  }

  void _rebuildRecognizer() {
    _recognizer = switch (engineName) {
      'cloud-vision' when apiKey.isNotEmpty =>
        CloudVisionRecognizer(pack, apiKey: apiKey),
      'local' => LocalRecognizer(pack),
      _ => MockRecognizer(pack),
    };
  }

  // -------------------------------------------------------------- teams --

  Future<void> saveTeam(Team team) async {
    await db.saveTeam(team);
    final index = teams.indexWhere((t) => t.id == team.id);
    if (index >= 0) {
      teams[index] = team;
    } else {
      teams.insert(0, team);
    }
    notifyListeners();
  }

  Future<void> deleteTeam(Team team) async {
    if (team.id != null) await db.deleteTeam(team.id!);
    teams.removeWhere((t) => t.id == team.id);
    notifyListeners();
  }

  // ----------------------------------------------------------- settings --

  Future<void> updateSettings({String? newApiKey, String? newEngine}) async {
    if (newApiKey != null) {
      apiKey = newApiKey;
      await db.setSetting(settingApiKey, newApiKey);
    }
    if (newEngine != null) {
      engineName = newEngine;
      await db.setSetting(settingEngine, newEngine);
    }
    _rebuildRecognizer();
    notifyListeners();
  }

  // ------------------------------------------------------------- battle --

  void startBattle(FormatSpec format, Team team, List<PokemonBuild> picks) {
    battle = BattleSession(format: format, team: team, picks: picks);
    notifyListeners();
  }

  void endBattle() {
    battle = null;
    notifyListeners();
  }

  /// Run the current recognition engine on a snapshot and merge the result
  /// into the battle (enemy side only — your side is already known). [screen]
  /// tells the engine whether it's reading the team-preview or battle screen.
  Future<RecognitionResult> runSnapshot(
    Uint8List imageBytes, {
    RecognitionScreen screen = RecognitionScreen.battle,
  }) async {
    final session = battle;
    if (session == null) {
      throw const RecognitionException('No battle in progress.');
    }
    final result = await _recognizer.recognize(
      imageBytes,
      context: BattleSnapshotContext(
        yourSpeciesIds: [for (final p in session.picks) p.speciesId],
        enemyFieldSlots: session.format.fieldSlots,
        screen: screen,
      ),
    );
    for (final slot in result.enemies) {
      session.addEnemy(
        slot.speciesId,
        mega: slot.isMega,
        hpPercent: slot.hpPercent,
      );
    }
    notifyListeners();
    return result;
  }

  void addEnemyManually(String speciesId) {
    battle?.addEnemy(speciesId);
    notifyListeners();
  }

  void removeEnemy(EnemyPokemon enemy) {
    battle?.removeEnemy(enemy);
    notifyListeners();
  }

  void mutateBattle(void Function() change) {
    change();
    notifyListeners();
  }
}

/// Simple InheritedNotifier so widgets can do `AppScope.of(context)`.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppScope>()!
      .notifier!;
}
