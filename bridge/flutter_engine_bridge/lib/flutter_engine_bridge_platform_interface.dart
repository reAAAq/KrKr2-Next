import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_engine_bridge_method_channel.dart';

abstract class FlutterEngineBridgePlatform extends PlatformInterface {
  /// Constructs a FlutterEngineBridgePlatform.
  FlutterEngineBridgePlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterEngineBridgePlatform _instance =
      MethodChannelFlutterEngineBridge();

  /// The default instance of [FlutterEngineBridgePlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterEngineBridge].
  static FlutterEngineBridgePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterEngineBridgePlatform] when
  /// they register themselves.
  static set instance(FlutterEngineBridgePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<int?> createTexture({required int width, required int height}) {
    throw UnimplementedError('createTexture() has not been implemented.');
  }

  Future<void> updateTextureRgba({
    required int textureId,
    required Uint8List rgba,
    required int width,
    required int height,
    required int rowBytes,
  }) {
    throw UnimplementedError('updateTextureRgba() has not been implemented.');
  }

  Future<void> disposeTexture({required int textureId}) {
    throw UnimplementedError('disposeTexture() has not been implemented.');
  }

  Future<void> attachNativeWindow({
    required int viewId,
    required int windowHandle,
  }) {
    throw UnimplementedError('attachNativeWindow() has not been implemented.');
  }

  Future<void> detachNativeWindow({required int viewId}) {
    throw UnimplementedError('detachNativeWindow() has not been implemented.');
  }

  Future<void> attachNativeView({
    required int viewId,
    required int viewHandle,
    int? windowHandle,
  }) {
    throw UnimplementedError('attachNativeView() has not been implemented.');
  }

  Future<void> detachNativeView({required int viewId}) {
    throw UnimplementedError('detachNativeView() has not been implemented.');
  }
}
