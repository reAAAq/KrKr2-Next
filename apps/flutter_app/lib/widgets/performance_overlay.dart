import 'dart:collection';

import 'package:flutter/material.dart';

/// A semi-transparent overlay that displays the current graphics API
/// (e.g. Metal, OpenGL ES) and a real-time FPS counter.
///
/// Place this in a [Stack] above the game surface.
class EnginePerformanceOverlay extends StatefulWidget {
  const EnginePerformanceOverlay({
    super.key,
    required this.rendererInfo,
  });

  /// The renderer info string from engine_get_renderer_info.
  final String rendererInfo;

  @override
  State<EnginePerformanceOverlay> createState() => EnginePerformanceOverlayState();
}

class EnginePerformanceOverlayState extends State<EnginePerformanceOverlay> {
  final Queue<double> _frameDurations = Queue<double>();
  static const int _sampleWindow = 60;
  double _fps = 0.0;
  DateTime _lastUpdate = DateTime.now();

  /// Call this from the tick loop with the delta time in milliseconds.
  void reportFrameDelta(double deltaMs) {
    _frameDurations.addLast(deltaMs);
    while (_frameDurations.length > _sampleWindow) {
      _frameDurations.removeFirst();
    }

    // Update displayed FPS at most once per 500ms to avoid jitter.
    final now = DateTime.now();
    if (now.difference(_lastUpdate).inMilliseconds >= 500 &&
        _frameDurations.isNotEmpty) {
      final avgDelta =
          _frameDurations.reduce((a, b) => a + b) / _frameDurations.length;
      _lastUpdate = now;
      if (mounted) {
        setState(() {
          _fps = avgDelta > 0 ? 1000.0 / avgDelta : 0.0;
        });
      }
    }
  }

  String _parseGraphicsApi(String rendererInfo) {
    if (rendererInfo.isEmpty) return 'Unknown';

    final lower = rendererInfo.toLowerCase();
    // ANGLE backend detection from GL_RENDERER string
    if (lower.contains('metal')) return 'Metal';
    if (lower.contains('vulkan')) return 'Vulkan';
    if (lower.contains('d3d11') || lower.contains('direct3d 11')) {
      return 'D3D11';
    }
    if (lower.contains('d3d9') || lower.contains('direct3d 9')) return 'D3D9';
    if (lower.contains('opengl es')) return 'OpenGL ES';
    if (lower.contains('opengl')) return 'OpenGL';

    // Fallback: return the first part before '|' if available
    final parts = rendererInfo.split('|');
    return parts.first.trim();
  }

  Color _fpsColor(double fps) {
    if (fps >= 50) return const Color(0xFF4CAF50); // green
    if (fps >= 30) return const Color(0xFFFFC107); // yellow
    return const Color(0xFFF44336); // red
  }

  @override
  Widget build(BuildContext context) {
    final graphicsApi = _parseGraphicsApi(widget.rendererInfo);
    final fpsText = _fps.toStringAsFixed(1);

    return Positioned(
      left: 8,
      top: MediaQuery.of(context).padding.top + 4,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                graphicsApi,
                style: const TextStyle(
                  color: Color(0xFFE0E0E0),
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                  height: 1.2,
                  decoration: TextDecoration.none,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '\u00B7',
                  style: TextStyle(
                    color: Color(0xFF757575),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              Text(
                '$fpsText FPS',
                style: TextStyle(
                  color: _fpsColor(_fps),
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                  height: 1.2,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
