import 'dart:typed_data';

export 'src/ffi/engine_bindings.dart'
    show
        kEngineInputEventBack,
        kEngineInputEventKeyDown,
        kEngineInputEventKeyUp,
        kEngineInputEventPointerDown,
        kEngineInputEventPointerMove,
        kEngineInputEventPointerScroll,
        kEngineInputEventPointerUp,
        kEngineInputEventTextInput,
        kEnginePixelFormatRgba8888,
        kEnginePixelFormatUnknown;
export 'src/ffi/engine_ffi.dart'
    show EngineFrameData, EngineFrameInfo, EngineInputEventData;

import 'flutter_engine_bridge_platform_interface.dart';
import 'src/ffi/engine_bindings.dart';
import 'src/ffi/engine_ffi.dart';

class FlutterEngineBridge {
  FlutterEngineBridge({
    FlutterEngineBridgePlatform? platform,
    EngineFfiBridge? ffiBridge,
    String? ffiLibraryPath,
  }) : _platform = platform ?? FlutterEngineBridgePlatform.instance,
       _ffiBridge =
           ffiBridge ?? EngineFfiBridge.tryCreate(libraryPath: ffiLibraryPath),
       _ffiInitializationError = ffiBridge == null
           ? EngineFfiBridge.lastCreateError
           : '';

  final FlutterEngineBridgePlatform _platform;
  final EngineFfiBridge? _ffiBridge;
  final String _ffiInitializationError;
  String _fallbackLastError = '';

  bool get isFfiAvailable => _ffiBridge != null;
  String get ffiInitializationError => _ffiInitializationError;

  Future<String?> getPlatformVersion() {
    return _platform.getPlatformVersion();
  }

  Future<String> getBackendDescription() async {
    if (isFfiAvailable) {
      return 'ffi';
    }
    final platformVersion = await _platform.getPlatformVersion();
    final versionLabel = platformVersion ?? 'unknown';
    return 'method_channel($versionLabel)';
  }

  Future<int> engineCreate({String? writablePath, String? cachePath}) async {
    return _withFfiCall(
      apiName: 'engine_create',
      call: (ffi) =>
          ffi.create(writablePath: writablePath, cachePath: cachePath),
    );
  }

  Future<int> engineDestroy() async {
    return _withFfiCall(
      apiName: 'engine_destroy',
      call: (ffi) => ffi.destroy(),
    );
  }

  Future<int> engineOpenGame(
    String gameRootPath, {
    String? startupScript,
  }) async {
    return _withFfiCall(
      apiName: 'engine_open_game',
      call: (ffi) => ffi.openGame(gameRootPath, startupScript: startupScript),
    );
  }

  Future<int> engineTick({int deltaMs = 16}) async {
    return _withFfiCall(
      apiName: 'engine_tick',
      call: (ffi) => ffi.tick(deltaMs: deltaMs),
    );
  }

  Future<int> enginePause() async {
    return _withFfiCall(apiName: 'engine_pause', call: (ffi) => ffi.pause());
  }

  Future<int> engineResume() async {
    return _withFfiCall(apiName: 'engine_resume', call: (ffi) => ffi.resume());
  }

  Future<int> engineSetOption({
    required String key,
    required String value,
  }) async {
    return _withFfiCall(
      apiName: 'engine_set_option',
      call: (ffi) => ffi.setOption(key: key, value: value),
    );
  }

  Future<int> engineSetSurfaceSize({
    required int width,
    required int height,
  }) async {
    return _withFfiCall(
      apiName: 'engine_set_surface_size',
      call: (ffi) => ffi.setSurfaceSize(width: width, height: height),
    );
  }

  Future<EngineFrameInfo?> engineGetFrameDesc() async {
    final ffi = _ffiBridge;
    if (ffi == null) {
      final platformVersion = await _platform.getPlatformVersion();
      final versionLabel = platformVersion ?? 'unknown';
      _fallbackLastError = _buildFallbackError(
        'FFI unavailable for engine_get_frame_desc. '
        'MethodChannel fallback active ($versionLabel).',
      );
      return null;
    }

    final frame = ffi.getFrameDesc();
    if (frame == null) {
      _fallbackLastError = ffi.lastError();
    } else {
      _fallbackLastError = '';
    }
    return frame;
  }

  Future<Uint8List?> engineReadFrameRgba() async {
    final ffi = _ffiBridge;
    if (ffi == null) {
      final platformVersion = await _platform.getPlatformVersion();
      final versionLabel = platformVersion ?? 'unknown';
      _fallbackLastError = _buildFallbackError(
        'FFI unavailable for engine_read_frame_rgba. '
        'MethodChannel fallback active ($versionLabel).',
      );
      return null;
    }

    final frameData = ffi.readFrameRgba();
    if (frameData == null) {
      _fallbackLastError = ffi.lastError();
    } else {
      _fallbackLastError = '';
    }
    return frameData;
  }

  Future<EngineFrameData?> engineReadFrame() async {
    final ffi = _ffiBridge;
    if (ffi == null) {
      final platformVersion = await _platform.getPlatformVersion();
      final versionLabel = platformVersion ?? 'unknown';
      _fallbackLastError = _buildFallbackError(
        'FFI unavailable for engine_read_frame_rgba. '
        'MethodChannel fallback active ($versionLabel).',
      );
      return null;
    }

    final frameData = ffi.readFrameRgbaWithDesc();
    if (frameData == null) {
      _fallbackLastError = ffi.lastError();
    } else {
      _fallbackLastError = '';
    }
    return frameData;
  }

  Future<int?> engineGetHostNativeWindow() async {
    final ffi = _ffiBridge;
    if (ffi == null) {
      final platformVersion = await _platform.getPlatformVersion();
      final versionLabel = platformVersion ?? 'unknown';
      _fallbackLastError = _buildFallbackError(
        'FFI unavailable for engine_get_host_native_window. '
        'MethodChannel fallback active ($versionLabel).',
      );
      return null;
    }

    final int? windowHandle = ffi.getHostNativeWindowHandle();
    if (windowHandle == null) {
      _fallbackLastError = ffi.lastError();
    } else {
      _fallbackLastError = '';
    }
    return windowHandle;
  }

  Future<int?> engineGetHostNativeView() async {
    final ffi = _ffiBridge;
    if (ffi == null) {
      final platformVersion = await _platform.getPlatformVersion();
      final versionLabel = platformVersion ?? 'unknown';
      _fallbackLastError = _buildFallbackError(
        'FFI unavailable for engine_get_host_native_view. '
        'MethodChannel fallback active ($versionLabel).',
      );
      return null;
    }

    final int? viewHandle = ffi.getHostNativeViewHandle();
    if (viewHandle == null) {
      _fallbackLastError = ffi.lastError();
    } else {
      _fallbackLastError = '';
    }
    return viewHandle;
  }

  Future<int> engineSendInput(EngineInputEventData event) async {
    return _withFfiCall(
      apiName: 'engine_send_input',
      call: (ffi) => ffi.sendInput(event),
    );
  }

  Future<int?> createTexture({required int width, required int height}) async {
    try {
      return await _platform.createTexture(width: width, height: height);
    } catch (error) {
      _fallbackLastError = 'createTexture failed: $error';
      return null;
    }
  }

  Future<bool> updateTextureRgba({
    required int textureId,
    required Uint8List rgba,
    required int width,
    required int height,
    required int rowBytes,
  }) async {
    try {
      await _platform.updateTextureRgba(
        textureId: textureId,
        rgba: rgba,
        width: width,
        height: height,
        rowBytes: rowBytes,
      );
      return true;
    } catch (error) {
      _fallbackLastError = 'updateTextureRgba failed: $error';
      return false;
    }
  }

  Future<void> disposeTexture({required int textureId}) async {
    try {
      await _platform.disposeTexture(textureId: textureId);
    } catch (error) {
      _fallbackLastError = 'disposeTexture failed: $error';
    }
  }

  Future<void> attachNativeWindow({
    required int viewId,
    required int windowHandle,
  }) async {
    try {
      await _platform.attachNativeWindow(
        viewId: viewId,
        windowHandle: windowHandle,
      );
    } catch (error) {
      _fallbackLastError = 'attachNativeWindow failed: $error';
      rethrow;
    }
  }

  Future<void> attachNativeView({
    required int viewId,
    required int viewHandle,
    int? windowHandle,
  }) async {
    try {
      await _platform.attachNativeView(
        viewId: viewId,
        viewHandle: viewHandle,
        windowHandle: windowHandle,
      );
    } catch (error) {
      _fallbackLastError = 'attachNativeView failed: $error';
      rethrow;
    }
  }

  Future<void> detachNativeWindow({required int viewId}) async {
    try {
      await _platform.detachNativeWindow(viewId: viewId);
    } catch (error) {
      _fallbackLastError = 'detachNativeWindow failed: $error';
      rethrow;
    }
  }

  Future<void> detachNativeView({required int viewId}) async {
    try {
      await _platform.detachNativeView(viewId: viewId);
    } catch (error) {
      _fallbackLastError = 'detachNativeView failed: $error';
      rethrow;
    }
  }

  Future<int> engineRuntimeApiVersion() async {
    final ffi = _ffiBridge;
    if (ffi == null) {
      final platformVersion = await _platform.getPlatformVersion();
      final versionLabel = platformVersion ?? 'unknown';
      _fallbackLastError = _buildFallbackError(
        'FFI unavailable for engine_get_runtime_api_version. '
        'MethodChannel fallback active ($versionLabel).',
      );
      return kEngineResultNotSupported;
    }

    final resultOrVersion = ffi.runtimeApiVersion();
    if (resultOrVersion < 0) {
      _fallbackLastError = ffi.lastError();
      return resultOrVersion;
    }

    _fallbackLastError = '';
    return resultOrVersion;
  }

  String engineGetLastError() {
    final ffi = _ffiBridge;
    if (ffi == null) {
      return _fallbackLastError;
    }
    return ffi.lastError();
  }

  Future<int> _withFfiCall({
    required String apiName,
    required int Function(EngineFfiBridge ffi) call,
    int fallbackResult = kEngineResultNotSupported,
  }) async {
    final ffi = _ffiBridge;
    if (ffi == null) {
      final platformVersion = await _platform.getPlatformVersion();
      final versionLabel = platformVersion ?? 'unknown';
      _fallbackLastError = _buildFallbackError(
        'FFI unavailable for $apiName. MethodChannel fallback active ($versionLabel).',
      );
      return fallbackResult;
    }

    final result = call(ffi);
    if (result != kEngineResultOk) {
      _fallbackLastError = ffi.lastError();
    } else {
      _fallbackLastError = '';
    }
    return result;
  }

  String _buildFallbackError(String base) {
    if (_ffiInitializationError.isEmpty) {
      return base;
    }
    return '$base\nFFI initialization error:\n$_ffiInitializationError';
  }
}
