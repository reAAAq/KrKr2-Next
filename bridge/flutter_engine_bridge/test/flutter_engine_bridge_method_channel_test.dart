import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_engine_bridge/flutter_engine_bridge_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelFlutterEngineBridge platform =
      MethodChannelFlutterEngineBridge();
  const MethodChannel channel = MethodChannel('flutter_engine_bridge');
  MethodCall? lastMethodCall;

  setUp(() {
    lastMethodCall = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          lastMethodCall = methodCall;
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });

  test('attachNativeWindow sends expected args', () async {
    await platform.attachNativeWindow(viewId: 3, windowHandle: 1234);

    expect(lastMethodCall?.method, 'attachNativeWindow');
    expect(lastMethodCall?.arguments, <String, Object>{
      'viewId': 3,
      'windowHandle': 1234,
    });
  });

  test(
    'attachNativeView sends expected args with optional window handle',
    () async {
      await platform.attachNativeView(
        viewId: 5,
        viewHandle: 5678,
        windowHandle: 9999,
      );

      expect(lastMethodCall?.method, 'attachNativeView');
      expect(lastMethodCall?.arguments, <String, Object>{
        'viewId': 5,
        'viewHandle': 5678,
        'windowHandle': 9999,
      });
    },
  );

  test('detachNativeView sends expected args', () async {
    await platform.detachNativeView(viewId: 7);

    expect(lastMethodCall?.method, 'detachNativeView');
    expect(lastMethodCall?.arguments, <String, Object>{'viewId': 7});
  });
}
