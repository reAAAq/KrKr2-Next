import 'dart:convert';

/// Represents a game entry in the launcher.
class GameInfo {
  GameInfo({
    required this.path,
    this.title,
    this.lastPlayed,
  });

  /// The root directory of the game.
  final String path;

  /// Display title. Falls back to the directory name if null.
  String? title;

  /// Last time the game was launched.
  DateTime? lastPlayed;

  /// Display name: user-set title or the last directory component.
  String get displayTitle {
    if (title != null && title!.isNotEmpty) return title!;
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.lastWhere((p) => p.isNotEmpty, orElse: () => path);
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'title': title,
        'lastPlayed': lastPlayed?.toIso8601String(),
      };

  factory GameInfo.fromJson(Map<String, dynamic> json) => GameInfo(
        path: json['path'] as String,
        title: json['title'] as String?,
        lastPlayed: json['lastPlayed'] != null
            ? DateTime.tryParse(json['lastPlayed'] as String)
            : null,
      );

  static List<GameInfo> listFromJsonString(String jsonString) {
    try {
      final List<dynamic> list = jsonDecode(jsonString) as List<dynamic>;
      return list
          .map((e) => GameInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String listToJsonString(List<GameInfo> games) {
    return jsonEncode(games.map((g) => g.toJson()).toList());
  }
}
