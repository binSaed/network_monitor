import 'package:flutter/services.dart';

class NativeNetworkChannel {
  static const _channel = MethodChannel('network_monitor');

  static Future<List<Map<String, dynamic>>> getNativeRecords() async {
    try {
      final result = await _channel.invokeMethod<List>('getRecords');
      if (result == null) return [];
      return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> setMaxRecords(int maxRecords) async {
    try {
      await _channel.invokeMethod('setMaxRecords', {'maxRecords': maxRecords});
    } catch (_) {}
  }

  static Future<({int txBytes, int rxBytes})> getTrafficStats() async {
    try {
      final result = await _channel.invokeMethod<Map>('getTrafficStats');
      return (
        txBytes: result?['txBytes'] as int? ?? 0,
        rxBytes: result?['rxBytes'] as int? ?? 0,
      );
    } catch (_) {
      return (txBytes: 0, rxBytes: 0);
    }
  }
}
