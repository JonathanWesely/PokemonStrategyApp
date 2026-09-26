/// Central app state: data pack, profiles (accounts), saved teams, match
/// history, settings, the active battle, and the pluggable recognition
/// engine.
library;

import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'data/data_pack.dart';
import 'models/battle_state.dart';
import 'models/match_record.dart';
import 'models/pokemon_build.dart';
import 'models/recognition_result.dart';
import 'models/regulation.dart';
import 'models/team.dart';
import 'recognition/auto_scan.dart';
import 'recognition/battle_events.dart';
import 'recognition/battle_ocr.dart';
import 'recognition/cloud_vision_recognizer.dart';
import 'recognition/local_recognizer.dart';
import 'recognition/mock_recognizer.dart';
import 'recognition/network_camera.dart';
import 'recognition/recognition_service.dart';
import 'recognition/sprite_matcher.dart';
import 'storage/app_database.dart';

// Settings keys.
const settingApiKey = 'anthropic_api_key'; // legacy name kept for migration
const settingEngine = 'recognition_engine'; // 'mock' | 'local' | 'api'
const settingApiProvider = 'api_provider'; // 'anthropic' | 'openai'
const settingApiBaseUrl = 'api_base_url';
const settingApiModel = 'api_model';
const settingActiveProfile = 'active_profile';
const settingOnboarded = 'onboarded';
const settingNetCamUrl = 'net_cam_url'; // MJPEG rig stream, e.g. http://ip:81/stream
const settingAutoScan = 'auto_scan'; // 'yes' (default) | 'no'
// 'yes' | 'no' — unset defaults to ON in debug builds, OFF in release.
const settingScanDiagnostics = 'scan_diagnostics';

class AppState extends ChangeNotifier {
  final DataPack pack;
  final AppDatabase db;

  /// Loads bundled assets (sprites, exemplar seeds); rootBundle in the app,
  /// File-based in tests.
  final ByteLoader assetLoader;

  /// Personal sprite-exemplar library (local engine's learning store).
  final ExemplarStore exemplars;

  /// On-device OCR engine; null where unavailable (tests inject fakes).
  final TextOcr? ocr;

  /// Diagnostics sink for the local sprite matcher (see [SpriteMatchDebug]);
  /// main.dart writes each report to documents/last_scan/ and the console.
  final void Function(SpriteMatchDebug report)? matchDebug;

  List<Profile> profiles = [];
  int activeProfileId = 1;
  bool onboarded = true;

  List<Team> teams = [];
  List<MatchRecord> matches = [];

  String apiKey = '';
  String engineName = 'local';
  String apiProvider = 'anthropic';
  String apiBaseUrl = '';
  String apiModel = '';
  String netCamUrl = '';

  /// Hands-free scanning from the rig (default ON): every battle connects
  /// to [netCamUrl] and scans by itself — team preview every 5 s until the
  /// picks are locked, then the 0.5 s in-match text tracker. Local engine
  /// only (an API engine at 2 scans/s would eat tokens).
  bool autoScanEnabled = true;

  /// Write frame/overlay/crops/report to documents/last_scan on every
  /// local team-preview scan. Debug builds default ON (unchanged); release
  /// builds get a Settings toggle so a TestFlight install can capture the
  /// exact scanner input for debugging.
  bool scanDiagnosticsEnabled = kDebugMode;
  BattleSession? battle;

  /// Live while a battle is running and auto-scan is possible; the battle
  /// screen shows its [AutoScanController.status] and the manual capture
  /// screen pauses it (the rig serves one stream client at a time).
  AutoScanController? autoScan;
  BattleEventTracker? _tracker;
  final NetworkCameraClient _netCamera = NetworkCameraClient();

  late RecognitionService _recognizer;

  AppState({
    required this.pack,
    required this.db,
    required this.assetLoader,
    ExemplarStore? exemplars,
    this.ocr,
    this.matchDebug,
  }) : exemplars = exemplars ?? ExemplarStore(loadBundled: assetLoader) {
    _rebuildRecognizer();
  }

  RecognitionService get recognizer => _recognizer;

  Profile? get activeProfile {
    for (final p in profiles) {
      if (p.id == activeProfileId) return p;
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  /// Load persisted profiles, teams, matches + settings. Call once at startup.
  Future<void> restore() async {
    profiles = await db.loadProfiles();
    final storedProfile = await db.getSetting(settingActiveProfile);
    activeProfileId = int.tryParse(storedProfile ?? '') ??
        (profiles.isEmpty ? 1 : profiles.first.id);
    onboarded = (await db.getSetting(settingOnboarded)) == 'yes';
    teams = await db.loadTeams(profileId: activeProfileId);
    matches = await db.loadMatches(profileId: activeProfileId);
    apiKey = await db.getSetting(settingApiKey) ?? '';
    var engine = await db.getSetting(settingEngine) ?? 'local';
    if (engine == 'cloud-vision') engine = 'api'; // legacy value
    engineName = engine;
    apiProvider = await db.getSetting(settingApiProvider) ?? 'anthropic';
    apiBaseUrl = await db.getSetting(settingApiBaseUrl) ?? '';
    apiModel = await db.getSetting(settingApiModel) ?? '';
    netCamUrl = await db.getSetting(settingNetCamUrl) ?? '';
    autoScanEnabled = (await db.getSetting(settingAutoScan)) != 'no';
    final diag = await db.getSetting(settingScanDiagnostics);
    scanDiagnosticsEnabled = diag == null ? kDebugMode : diag == 'yes';
    _rebuildRecognizer();
    notifyListeners();
  }

  void _rebuildRecognizer() {
    _recognizer = switch (engineName) {
      'api' when apiKey.isNotEmpty => ApiRecognizer(
          pack,
          apiKey: apiKey,
          provider: apiProvider == 'openai'
              ? ApiProvider.openAiCompatible
              : ApiProvider.anthropic,
          model: apiModel.trim().isEmpty ? null : apiModel.trim(),
          baseUrl: apiBaseUrl.trim().isEmpty ? null : apiBaseUrl.trim(),
        ),
      'mock' => MockRecognizer(pack),
      _ => LocalRecognizer(
          pack,
          matcher: SpriteMatcher(pack,
              loadBytes: assetLoader,
              exemplars: exemplars,
              onDebug: scanDiagnosticsEnabled ? matchDebug : null),
          ocr: ocr,
        ),
    };
  }

  // ----------------------------------------------------------- profiles --

  Future<void> switchProfile(int profileId) async {
    autoScan?.stop();
    autoScan = null;
    _tracker = null;
    activeProfileId = profileId;
    await db.setSetting(settingActiveProfile, '$profileId');
    teams = await db.loadTeams(profileId: profileId);
    matches = await db.loadMatches(profileId: profileId);
    battle = null;
    notifyListeners();
  }

  Future<Profile> createProfile(String name) async {
    final profile = await db.createProfile(name);
    profiles = await db.loadProfiles();
    await switchProfile(profile.id);
    return profile;
  }

  Future<void> renameActiveProfile(String name) async {
    await db.renameProfile(activeProfileId, name);
    profiles = await db.loadProfiles();
    notifyListeners();
  }

  Future<void> completeOnboarding(String name) async {
    if (name.trim().isNotEmpty) {
      await db.renameProfile(activeProfileId, name.trim());
      profiles = await db.loadProfiles();
    }
    onboarded = true;
    await db.setSetting(settingOnboarded, 'yes');
    notifyListeners();
  }

  // -------------------------------------------------------------- teams --

  Future<void> saveTeam(Team team) async {
    await db.saveTeam(team, profileId: activeProfileId);
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

  Future<void> updateSettings({
    String? newApiKey,
    String? newEngine,
    String? newApiProvider,
    String? newApiBaseUrl,
    String? newApiModel,
    String? newNetCamUrl,
    bool? newAutoScanEnabled,
  }) async {
    if (newApiKey != null) {
      apiKey = newApiKey;
      await db.setSetting(settingApiKey, newApiKey);
    }
    if (newEngine != null) {
      engineName = newEngine;
      await db.setSetting(settingEngine, newEngine);
    }
    if (newApiProvider != null) {
      apiProvider = newApiProvider;
      await db.setSetting(settingApiProvider, newApiProvider);
    }
    if (newApiBaseUrl != null) {
      apiBaseUrl = newApiBaseUrl;
      await db.setSetting(settingApiBaseUrl, newApiBaseUrl);
    }
    if (newApiModel != null) {
      apiModel = newApiModel;
      await db.setSetting(settingApiModel, newApiModel);
    }
    if (newNetCamUrl != null) {
      netCamUrl = newNetCamUrl;
      await db.setSetting(settingNetCamUrl, newNetCamUrl);
    }
    if (newAutoScanEnabled != null) {
      autoScanEnabled = newAutoScanEnabled;
      await db.setSetting(settingAutoScan, newAutoScanEnabled ? 'yes' : 'no');
    }
    _rebuildRecognizer();
    // A new engine / rig address / toggle can change whether auto-scan runs.
    if (battle != null) _startAutoScan();
    notifyListeners();
  }

  Future<void> setScanDiagnostics(bool enabled) async {
    scanDiagnosticsEnabled = enabled;
    await db.setSetting(settingScanDiagnostics, enabled ? 'yes' : 'no');
    _rebuildRecognizer();
    notifyListeners();
  }

  // ------------------------------------------------------------- battle --

  /// Open a battle. Picks are usually chosen later, INSIDE the battle
  /// (Battle tab), after scouting the enemy on Team Preview — the same order
  /// the game itself forces.
  void startBattle(FormatSpec format, Team team,
      {List<PokemonBuild>? picks}) {
    battle = BattleSession(format: format, team: team, picks: picks);
    _tracker = BattleEventTracker(pack, battle!);
    _startAutoScan();
    notifyListeners();
  }

  /// Why auto-scan is not running (for the battle screen's status chip);
  /// null when it IS running.
  String? get autoScanUnavailableReason {
    if (!autoScanEnabled) return 'Auto-scan is off (Settings)';
    if (engineName != 'local') {
      return 'Auto-scan needs the Local engine (Settings)';
    }
    if (normalizeStreamUrl(netCamUrl) == null) {
      return 'No rig address saved yet — connect once via Manually scan';
    }
    return null;
  }

  void _startAutoScan() {
    // Keep the paused state across a restart (a settings change while the
    // manual capture screen holds the rig's single stream slot must not
    // start a second connection).
    final wasPaused = autoScan?.isPaused ?? false;
    autoScan?.stop();
    autoScan = null;
    if (battle == null || autoScanUnavailableReason != null) return;
    autoScan = AutoScanController(
      framesOf: _netCamera.frames,
      urlOf: () => normalizeStreamUrl(netCamUrl),
      phaseOf: () {
        final session = battle;
        if (session == null) return AutoScanPhase.off;
        return session.picksChosen ? AutoScanPhase.battle : AutoScanPhase.preview;
      },
      onFrame: (frame, phase) async {
        try {
          if (phase == AutoScanPhase.preview) {
            await runSnapshot(frame, screen: RecognitionScreen.preview);
          } else {
            await runSnapshot(frame, screen: RecognitionScreen.battle);
          }
        } on RecognitionException {
          // No panels in this frame (menu open, scene transition) — fine,
          // the next tick gets another look.
        }
      },
    );
    if (wasPaused) autoScan!.pause('paused while the camera view is open');
    autoScan!.start();
  }

  /// Lock in (or change) which of your six you're bringing.
  void setPicks(List<PokemonBuild> picks) {
    battle?.setPicks(picks);
    notifyListeners();
  }

  /// End the battle; when [result] is 'win' | 'loss' | 'unknown' and there is
  /// anything worth keeping, the session is saved to match history.
  Future<void> endBattle({String result = 'unknown', bool save = true}) async {
    autoScan?.stop();
    autoScan = null;
    _tracker = null;
    final session = battle;
    battle = null;
    if (save &&
        session != null &&
        (session.enemies.isNotEmpty || session.enemyPreview.isNotEmpty)) {
      final record = await db.saveMatch(MatchRecord(
        profileId: activeProfileId,
        date: DateTime.now().toIso8601String(),
        formatId: session.format.id,
        formatName: session.format.name,
        teamName: session.team.name,
        result: result,
        snapshot: session.toSnapshotJson(),
      ));
      matches.insert(0, record);
    }
    notifyListeners();
  }

  Future<void> deleteMatch(MatchRecord record) async {
    if (record.id != null) await db.deleteMatch(record.id!);
    matches.removeWhere((m) => m.id == record.id);
    notifyListeners();
  }

  /// Run the current recognition engine on a snapshot and merge the result
  /// into the battle. [screen] selects the pipeline: the team-preview scan
  /// fills the enemy roster boxes; the battle scan updates who is on the
  /// field.
  Future<RecognitionResult> runSnapshot(
    Uint8List imageBytes, {
    RecognitionScreen screen = RecognitionScreen.battle,
  }) async {
    final session = battle;
    if (session == null) {
      throw const RecognitionException('No battle in progress.');
    }
    if (screen == RecognitionScreen.battle &&
        engineName == 'local' &&
        ocr != null) {
      return _runBattleTextScan(session, imageBytes);
    }
    final result = await _recognizer.recognize(
      imageBytes,
      context: BattleSnapshotContext(
        // Preview screen shows your whole six; the battle screen only your
        // picks (which may not be locked yet during scouting).
        yourSpeciesIds: screen == RecognitionScreen.preview
            ? [for (final b in session.team.builds) b.speciesId]
            : [for (final p in session.picks) p.speciesId],
        enemyFieldSlots: session.format.fieldSlots,
        enemyTeamSize: session.format.teamSize,
        screen: screen,
      ),
    );
    if (screen == RecognitionScreen.preview) {
      _mergePreview(session, result);
    } else {
      _applyBattleSlots(session, result);
    }
    notifyListeners();
    return result;
  }

  /// Local-engine battle scan: OCR ONCE, then feed the same lines to both
  /// the name-banner matcher (who is on the field, HP) and the in-match
  /// event tracker (moves, abilities, items, Trick Room, speed order).
  /// Both the manual "Manually scan" flow and the 0.5 s auto-scan land
  /// here, so a manual snap teaches the tracker too.
  Future<RecognitionResult> _runBattleTextScan(
      BattleSession session, Uint8List imageBytes) async {
    final lines = await ocr!.readLines(imageBytes);
    final slots = BattleTextMatcher(pack).match(
      lines,
      BattleSnapshotContext(
        yourSpeciesIds: [for (final p in session.picks) p.speciesId],
        enemyFieldSlots: session.format.fieldSlots,
        enemyTeamSize: session.format.teamSize,
        screen: RecognitionScreen.battle,
      ),
    );
    final result = RecognitionResult(slots: slots, engine: 'local');
    _applyBattleSlots(session, result);
    final events = _tracker?.consume(lines) ?? const <BattleEvent>[];
    if (slots.isEmpty && events.isEmpty) {
      throw const RecognitionException(
          'No Pokemon names found in this photo — make sure the name banners '
          'are visible, or add the enemy manually.');
    }
    notifyListeners();
    return result;
  }

  /// Battle-screen result -> session: enemies join/update the field, and
  /// recognized Pokemon of YOURS sync the on-field chips.
  void _applyBattleSlots(BattleSession session, RecognitionResult result) {
    for (final slot in result.enemies) {
      session.addEnemy(
        slot.speciesId,
        mega: slot.isMega,
        hpPercent: slot.hpPercent,
      );
    }
    final yoursSeen = result.yours.map((s) => s.speciesId).toSet();
    if (yoursSeen.isEmpty) return;
    for (var i = 0; i < session.picks.length; i++) {
      if (yoursSeen.contains(session.picks[i].speciesId)) {
        session.activePickIndexes.add(i);
      }
    }
    // Too many actives now? Drop the ones the screen did NOT show.
    if (session.activePickIndexes.length > session.format.fieldSlots) {
      final keep = session.activePickIndexes
          .where((i) => yoursSeen.contains(session.picks[i].speciesId))
          .toList();
      if (keep.length <= session.format.fieldSlots) {
        final rest = session.activePickIndexes
            .where((i) => !keep.contains(i))
            .take(session.format.fieldSlots - keep.length)
            .toList(); // materialize BEFORE the clear() below
        session.activePickIndexes
          ..clear()
          ..addAll([...keep, ...rest]);
      }
    }
  }

  void _mergePreview(BattleSession session, RecognitionResult result) {
    final confirmed = [
      for (final s in session.enemyPreview)
        if (s.confirmed) s
    ];
    final next = <PreviewSlot>[];
    for (final slot in result.enemies.take(session.format.teamSize)) {
      final existing = session.previewSlotFor(slot.speciesId);
      if (existing != null && existing.confirmed) {
        next.add(existing);
        confirmed.remove(existing);
        continue;
      }
      next.add(PreviewSlot(
        slot.speciesId,
        confidence: slot.confidence,
        confirmed: false,
      )
        ..alternatives = slot.alternatives
        ..spriteCrop = slot.spriteCrop);
    }
    // Never lose slots the user already confirmed.
    for (final s in confirmed) {
      if (next.length < session.format.teamSize) next.add(s);
    }
    session.enemyPreview
      ..clear()
      ..addAll(next);
  }

  /// Confirm (or correct) a preview slot. Confirmations feed the segmented
  /// sprite back into the exemplar library so the local matcher learns.
  void confirmPreviewSlot(PreviewSlot slot, String speciesId) {
    final crop = slot.spriteCrop;
    if (crop != null) {
      exemplars.add(speciesId, crop);
    }
    slot
      ..speciesId = speciesId
      ..confirmed = true
      ..confidence = 1.0
      ..alternatives = const []
      ..spriteCrop = null;
    notifyListeners();
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
