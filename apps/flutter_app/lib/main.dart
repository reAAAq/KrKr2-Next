import 'package:flutter/material.dart';
import 'package:flutter_engine_bridge/flutter_engine_bridge.dart';

void main() {
  runApp(const FlutterShellApp());
}

class FlutterShellApp extends StatelessWidget {
  const FlutterShellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Krkr2 Flutter Shell',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const EngineBridgeHomePage(),
    );
  }
}

class EngineBridgeHomePage extends StatefulWidget {
  const EngineBridgeHomePage({super.key});

  @override
  State<EngineBridgeHomePage> createState() => _EngineBridgeHomePageState();
}

class _EngineBridgeHomePageState extends State<EngineBridgeHomePage> {
  static const int _engineResultOk = 0;
  static const String _loading = 'Loading bridge info...';

  final FlutterEngineBridge _bridge = FlutterEngineBridge();
  String _backendInfo = _loading;
  String _platformInfo = _loading;
  String _engineStatus = 'Not created';
  String _lastResult = 'N/A';
  String _lastError = 'Last error: <empty>';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadBridgeInfo();
  }

  Future<void> _loadBridgeInfo() async {
    setState(() {
      _busy = true;
    });
    try {
      final String backend = await _bridge.getBackendDescription();
      final String? platform = await _bridge.getPlatformVersion();
      final String error = _bridge.engineGetLastError();
      if (!mounted) return;
      setState(() {
        _backendInfo = backend;
        _platformInfo = platform ?? 'No platform info returned from plugin.';
        _lastError = error.isEmpty ? 'Last error: <empty>' : 'Last error: $error';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _backendInfo = 'Bridge detect failed: $e';
        _platformInfo = 'Plugin call failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _engineCreate() async {
    setState(() {
      _busy = true;
    });
    try {
      final int result = await _bridge.engineCreate();
      final String error = _bridge.engineGetLastError();
      if (!mounted) return;
      setState(() {
        _lastResult = 'engine_create => $result';
        _engineStatus = result == _engineResultOk ? 'Created' : 'Create failed';
        _lastError = error.isEmpty ? 'Last error: <empty>' : 'Last error: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _engineDestroy() async {
    setState(() {
      _busy = true;
    });
    try {
      final int result = await _bridge.engineDestroy();
      final String error = _bridge.engineGetLastError();
      if (!mounted) return;
      setState(() {
        _lastResult = 'engine_destroy => $result';
        _engineStatus = result == _engineResultOk ? 'Not created' : 'Destroy failed';
        _lastError = error.isEmpty ? 'Last error: <empty>' : 'Last error: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Krkr2 Flutter Shell')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Flutter shell ready.\nEngine bridge status:',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Backend: $_backendInfo',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Platform: $_platformInfo',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Engine status: $_engineStatus',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Last result: $_lastResult',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _lastError,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (_busy) const CircularProgressIndicator(),
              if (_busy) const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _busy ? null : _loadBridgeInfo,
                    child: const Text('Refresh bridge info'),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _engineCreate,
                    child: const Text('engine_create'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _engineDestroy,
                    child: const Text('engine_destroy'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
