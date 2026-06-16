import 'dart:io';

import 'package:flutter/services.dart';

class LaunchArgsService {
  static const MethodChannel _channel = MethodChannel('krkr2next/launch_args');

  static Future<String?> getInitialGamePath() async {
    if (!Platform.isMacOS) {
      return null;
    }

    final List<Object?>? rawArgs = await _channel.invokeListMethod<Object?>(
      'getLaunchArguments',
    );
    if (rawArgs == null || rawArgs.isEmpty) {
      return null;
    }

    final args = rawArgs.whereType<String>().toList(growable: false);
    for (var i = 0; i < args.length; i++) {
      final arg = args[i].trim();
      if (arg.isEmpty) {
        continue;
      }

      if (arg == '--game' && i + 1 < args.length) {
        return _normalizePath(args[i + 1]);
      }

      if (arg.startsWith('--game=')) {
        return _normalizePath(arg.substring('--game='.length));
      }

      if (!arg.startsWith('-')) {
        return _normalizePath(arg);
      }
    }

    return null;
  }

  static String? _normalizePath(String rawPath) {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    try {
      final entityType = FileSystemEntity.typeSync(trimmed);
      if (entityType == FileSystemEntityType.notFound) {
        return null;
      }
      return File(trimmed).absolute.path;
    } catch (_) {
      return null;
    }
  }
}
