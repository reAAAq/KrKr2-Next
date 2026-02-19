import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../engine/engine_bridge.dart';

const String _nativeSurfaceViewType =
    'flutter_engine_bridge/native_engine_surface';

class EngineNativeSurface extends StatefulWidget {
  const EngineNativeSurface({
    super.key,
    required this.bridge,
    required this.active,
    this.onLog,
    this.onError,
  });

  final EngineBridge bridge;
  final bool active;
  final ValueChanged<String>? onLog;
  final ValueChanged<String>? onError;

  @override
  State<EngineNativeSurface> createState() => _EngineNativeSurfaceState();
}

class _EngineNativeSurfaceState extends State<EngineNativeSurface> {
  Timer? _windowHandlePollTimer;
  bool _windowHandleQueryInFlight = false;
  bool _attachInFlight = false;
  bool _attached = false;

  int _surfaceWidth = 0;
  int _surfaceHeight = 0;
  int? _nativeWindowHandle;
  int? _platformViewId;
  double _devicePixelRatio = 1.0;

  @override
  void initState() {
    super.initState();
    _reconcileActiveState();
  }

  @override
  void didUpdateWidget(covariant EngineNativeSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bridge != widget.bridge) {
      unawaited(_detachIfNeeded());
      _nativeWindowHandle = null;
    }
    if (!widget.active && oldWidget.active) {
      unawaited(_detachIfNeeded());
    }
    if (oldWidget.active != widget.active ||
        oldWidget.bridge != widget.bridge) {
      _reconcileActiveState();
    }
  }

  @override
  void dispose() {
    _windowHandlePollTimer?.cancel();
    unawaited(_detachIfNeeded());
    super.dispose();
  }

  void _reconcileActiveState() {
    if (!widget.active || !Platform.isMacOS) {
      _windowHandlePollTimer?.cancel();
      _windowHandlePollTimer = null;
      return;
    }

    _windowHandlePollTimer ??= Timer.periodic(
      const Duration(milliseconds: 300),
      (_) {
        unawaited(_ensureNativeWindowHandle());
        unawaited(_tryAttach());
      },
    );

    unawaited(_ensureNativeWindowHandle());
    unawaited(_tryAttach());
  }

  Future<void> _ensureSurfaceSize(Size size, double devicePixelRatio) async {
    if (!widget.active) {
      return;
    }
    _devicePixelRatio = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    final int width = (size.width * _devicePixelRatio).round().clamp(1, 16384);
    final int height = (size.height * _devicePixelRatio).round().clamp(
      1,
      16384,
    );
    if (width == _surfaceWidth && height == _surfaceHeight) {
      return;
    }

    _surfaceWidth = width;
    _surfaceHeight = height;
    final int result = await widget.bridge.engineSetSurfaceSize(
      width: width,
      height: height,
    );
    if (result != 0) {
      _reportError(
        'engine_set_surface_size failed: result=$result, error=${widget.bridge.engineGetLastError()}',
      );
      return;
    }
    widget.onLog?.call(
      'native surface resized: ${width}x$height (dpr=${_devicePixelRatio.toStringAsFixed(2)})',
    );
  }

  Future<void> _ensureNativeWindowHandle() async {
    if (!widget.active ||
        !Platform.isMacOS ||
        _windowHandleQueryInFlight ||
        _nativeWindowHandle != null) {
      return;
    }

    _windowHandleQueryInFlight = true;
    try {
      final int? handle = await widget.bridge.engineGetHostNativeWindow();
      if (!mounted || !widget.active) {
        return;
      }
      if (handle == null || handle == 0) {
        return;
      }

      setState(() {
        _nativeWindowHandle = handle;
      });
      widget.onLog?.call(
        'native window handle ready: 0x${handle.toRadixString(16)}',
      );
      await _tryAttach();
    } catch (error) {
      _reportError('query native window handle failed: $error');
    } finally {
      _windowHandleQueryInFlight = false;
    }
  }

  Future<void> _tryAttach() async {
    if (!widget.active || !Platform.isMacOS || _attachInFlight || _attached) {
      return;
    }
    final int? viewId = _platformViewId;
    final int? windowHandle = _nativeWindowHandle;
    if (viewId == null || windowHandle == null || windowHandle == 0) {
      return;
    }

    _attachInFlight = true;
    try {
      await widget.bridge.attachNativeWindow(
        viewId: viewId,
        windowHandle: windowHandle,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _attached = true;
      });
      widget.onLog?.call('native window attached (viewId=$viewId)');
    } catch (error) {
      _reportError('attach native window failed: $error');
    } finally {
      _attachInFlight = false;
    }
  }

  Future<void> _detachIfNeeded() async {
    if (!_attached) {
      return;
    }
    final int? viewId = _platformViewId;
    _attached = false;
    if (viewId == null) {
      return;
    }
    try {
      await widget.bridge.detachNativeWindow(viewId: viewId);
      widget.onLog?.call('native window detached (viewId=$viewId)');
    } catch (error) {
      _reportError('detach native window failed: $error');
    }
  }

  void _onPlatformViewCreated(int viewId) {
    setState(() {
      _platformViewId = viewId;
      _attached = false;
    });
    unawaited(_tryAttach());
  }

  void _reportError(String message) {
    widget.onError?.call(message);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Size size = Size(constraints.maxWidth, constraints.maxHeight);
          final double dpr = MediaQuery.of(context).devicePixelRatio;
          unawaited(_ensureSurfaceSize(size, dpr));
          if (widget.active && Platform.isMacOS) {
            unawaited(_ensureNativeWindowHandle());
            unawaited(_tryAttach());
          }

          return Container(
            decoration: BoxDecoration(
              color: Colors.black,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!Platform.isMacOS)
                  const Center(
                    child: Text(
                      'Native view is only available on macOS',
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                else
                  AppKitView(
                    viewType: _nativeSurfaceViewType,
                    onPlatformViewCreated: _onPlatformViewCreated,
                  ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'surface:${_surfaceWidth}x$_surfaceHeight  '
                      'view:${_platformViewId ?? "-"}  '
                      'handle:${_nativeWindowHandle != null ? "0x${_nativeWindowHandle!.toRadixString(16)}" : "-"}  '
                      '${_attached ? "attached" : "pending"}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
