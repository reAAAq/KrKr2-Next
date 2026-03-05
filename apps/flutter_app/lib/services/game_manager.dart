import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/prefs_keys.dart';
import '../models/game_info.dart';

/// Manages persisted game list using SharedPreferences.
class GameManager {
  static const String _storageKey = 'krkr2_game_list';
  static const int _maxSessionSeconds = 86400; // 24h cap per session
  static const int _maxSettledSessionIds = 64;

  List<GameInfo> _games = [];

  List<GameInfo> get games => List.unmodifiable(_games);

  /// Load the game list from persistent storage.
  /// Call [applyPendingPlaySession] after this to credit play time if the app was last closed while in a game.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      _games = GameInfo.listFromJsonString(raw);
    }
  }

  /// If a pending play session exists (app was closed/killed while in game),
  /// add that duration (once) and clear the pending session.
  Future<void> applyPendingPlaySession() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(PrefsKeys.pendingPlaySession);
    if (jsonStr == null || jsonStr.isEmpty) return;

    Map<String, dynamic>? data;
    try {
      data = jsonDecode(jsonStr) as Map<String, dynamic>?;
    } catch (_) {
      await prefs.remove(PrefsKeys.pendingPlaySession);
      return;
    }

    data = data ?? <String, dynamic>{};
    final path = data['path'] as String?;
    if (path == null || path.isEmpty) {
      await prefs.remove(PrefsKeys.pendingPlaySession);
      return;
    }

    if (!_games.any((g) => g.path == path)) {
      await prefs.remove(PrefsKeys.pendingPlaySession);
      return;
    }

    // v2 format: {sessionId,path,activeSeconds,isRunning,runningSinceEpochMs}
    final sessionId = data['sessionId'] as String?;
    if (sessionId != null && sessionId.isNotEmpty) {
      final settledIds = _readSettledSessionIds(prefs);
      if (settledIds.contains(sessionId)) {
        await prefs.remove(PrefsKeys.pendingPlaySession);
        return;
      }

      int seconds = _toInt(data['activeSeconds']);
      final isRunning = data['isRunning'] == true;
      final runningSinceEpochMs = _toInt(data['runningSinceEpochMs']);
      if (isRunning && runningSinceEpochMs > 0) {
        final nowEpochMs = DateTime.now().millisecondsSinceEpoch;
        final extra = (nowEpochMs - runningSinceEpochMs) ~/ 1000;
        if (extra > 0) seconds += extra;
      }
      if (seconds > _maxSessionSeconds) {
        seconds = _maxSessionSeconds;
      }
      if (seconds > 0) {
        await addPlayDuration(path, seconds);
      }
      await _appendSettledSessionId(prefs, sessionId);
      await prefs.remove(PrefsKeys.pendingPlaySession);
      return;
    }

    // v1 fallback: {path,startTime}
    final startStr = data['startTime'] as String?;
    final start = startStr != null ? DateTime.tryParse(startStr) : null;
    if (start == null) {
      await prefs.remove(PrefsKeys.pendingPlaySession);
      return;
    }

    int seconds = DateTime.now().difference(start).inSeconds;
    if (seconds > _maxSessionSeconds) {
      seconds = _maxSessionSeconds;
    }
    if (seconds > 0) {
      await addPlayDuration(path, seconds);
    }
    await prefs.remove(PrefsKeys.pendingPlaySession);
  }

  /// Record a completed play session exactly once.
  /// Duplicate [sessionId] submissions are ignored.
  Future<void> recordPlaySession(
    String path,
    int seconds,
    String sessionId,
  ) async {
    if (sessionId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final settledIds = _readSettledSessionIds(prefs);
    if (settledIds.contains(sessionId)) return;

    int safeSeconds = seconds;
    if (safeSeconds > _maxSessionSeconds) {
      safeSeconds = _maxSessionSeconds;
    }
    if (safeSeconds > 0) {
      await addPlayDuration(path, safeSeconds);
    }
    await _appendSettledSessionId(prefs, sessionId);
  }

  /// Save the current game list to persistent storage.
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, GameInfo.listToJsonString(_games));
  }

  /// Add a game. Returns true if added (not a duplicate).
  Future<bool> addGame(GameInfo game) async {
    // Deduplicate by path
    if (_games.any((g) => g.path == game.path)) {
      return false;
    }
    _games.add(game);
    await _save();
    return true;
  }

  /// Remove a game by path.
  Future<void> removeGame(String path) async {
    _games.removeWhere((g) => g.path == path);
    await _save();
  }

  /// Update the lastPlayed timestamp for a game.
  Future<void> markPlayed(String path) async {
    final index = _games.indexWhere((g) => g.path == path);
    if (index >= 0) {
      _games[index].lastPlayed = DateTime.now();
      await _save();
    }
  }

  /// Add play duration (in seconds) for a game. Called when leaving the game page.
  Future<void> addPlayDuration(String path, int seconds) async {
    if (seconds <= 0) return;
    final index = _games.indexWhere((g) => g.path == path);
    if (index >= 0) {
      final current = _games[index].playDurationSeconds ?? 0;
      _games[index].playDurationSeconds = current + seconds;
      await _save();
    }
  }

  /// Rename a game's title.
  Future<void> renameGame(String path, String newTitle) async {
    final index = _games.indexWhere((g) => g.path == path);
    if (index >= 0) {
      _games[index].title = newTitle;
      await _save();
    }
  }

  /// Update a game's path (e.g. when iOS sandbox container UUID changes).
  Future<void> updateGamePath(String oldPath, String newPath) async {
    final index = _games.indexWhere((g) => g.path == oldPath);
    if (index >= 0) {
      _games[index].path = newPath;
      await _save();
    }
  }

  /// Set a custom cover image path for a game.
  Future<void> setCoverImage(String path, String? coverPath) async {
    final index = _games.indexWhere((g) => g.path == path);
    if (index >= 0) {
      _games[index].coverPath = coverPath;
      await _save();
    }
  }

  /// Set developer / producer name for a game (e.g. from scraping).
  Future<void> setDeveloper(String path, String? developer) async {
    final index = _games.indexWhere((g) => g.path == path);
    if (index >= 0) {
      _games[index].developer = developer;
      await _save();
    }
  }

  List<String> _readSettledSessionIds(SharedPreferences prefs) {
    return List<String>.from(
      prefs.getStringList(PrefsKeys.settledPlaySessionIds) ?? const <String>[],
    );
  }

  Future<void> _appendSettledSessionId(
    SharedPreferences prefs,
    String sessionId,
  ) async {
    final ids = _readSettledSessionIds(prefs);
    ids.removeWhere((e) => e == sessionId);
    ids.add(sessionId);
    final start = ids.length > _maxSettledSessionIds
        ? ids.length - _maxSettledSessionIds
        : 0;
    await prefs.setStringList(
      PrefsKeys.settledPlaySessionIds,
      ids.sublist(start),
    );
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}
