import 'dart:math';

import 'native_channel.dart';
import 'network_request_record.dart';

class NetworkMonitorService {
  NetworkMonitorService._();

  static final NetworkMonitorService instance = NetworkMonitorService._();

  int _maxRecords = 1000;

  final List<NetworkRequestRecord> _records = [];
  int _baselineTxBytes = 0;
  int _baselineRxBytes = 0;
  int _latestOsTxBytes = 0;
  int _latestOsRxBytes = 0;
  bool _initialized = false;
  bool _osStatsAvailable = false;

  bool get isInitialized => _initialized;

  int get maxRecords => _maxRecords;

  List<NetworkRequestRecord> get records => List.unmodifiable(_records);

  bool get osStatsAvailable => _osStatsAvailable;

  Future<void> init({int maxRecords = 1000, int maxNativeRecords = 500}) async {
    if (_initialized) return;
    _maxRecords = maxRecords;
    _initialized = true;
    await NativeNetworkChannel.setMaxRecords(maxNativeRecords);
    try {
      final stats = await NativeNetworkChannel.getTrafficStats();
      if (stats.txBytes >= 0 && stats.rxBytes >= 0) {
        _osStatsAvailable = true;
        _baselineTxBytes = stats.txBytes;
        _baselineRxBytes = stats.rxBytes;
        _latestOsTxBytes = stats.txBytes;
        _latestOsRxBytes = stats.rxBytes;
      }
    } catch (_) {}
  }

  void addRecord(NetworkRequestRecord record) {
    _records.add(record);
    if (_records.length > _maxRecords) {
      _records.removeRange(0, _records.length - _maxRecords);
    }
  }

  void clearRecords() {
    _records.clear();
  }

  static bool isDartSource(String source) => source == 'dio' || source == 'http';

  int get totalDioTxBytes => _records
      .where((r) => isDartSource(r.source))
      .fold(0, (sum, r) => sum + r.requestSizeBytes);

  int get totalDioRxBytes => _records
      .where((r) => isDartSource(r.source))
      .fold(0, (sum, r) => sum + r.responseSizeBytes);

  int get totalNativeTxBytes => _records
      .where((r) => !isDartSource(r.source))
      .fold(0, (sum, r) => sum + r.requestSizeBytes);

  int get totalNativeRxBytes => _records
      .where((r) => !isDartSource(r.source))
      .fold(0, (sum, r) => sum + r.responseSizeBytes);

  int get untrackedTxBytes => _osStatsAvailable
      ? max(0, (_latestOsTxBytes - _baselineTxBytes) - totalDioTxBytes - totalNativeTxBytes)
      : 0;

  int get untrackedRxBytes => _osStatsAvailable
      ? max(0, (_latestOsRxBytes - _baselineRxBytes) - totalDioRxBytes - totalNativeRxBytes)
      : 0;

  int get totalTxBytes => totalDioTxBytes + totalNativeTxBytes + untrackedTxBytes;

  int get totalRxBytes => totalDioRxBytes + totalNativeRxBytes + untrackedRxBytes;

  Future<void> fetchNativeRecords() async {
    try {
      final nativeRecords = await NativeNetworkChannel.getNativeRecords();
      for (final map in nativeRecords) {
        addRecord(NetworkRequestRecord(
          url: map['url'] as String? ?? '',
          method: map['method'] as String? ?? 'GET',
          statusCode: map['statusCode'] as int? ?? 0,
          requestSizeBytes: map['requestSizeBytes'] as int? ?? 0,
          responseSizeBytes: map['responseSizeBytes'] as int? ?? 0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int? ?? 0),
          duration: Duration(milliseconds: map['durationMs'] as int? ?? 0),
          source: map['source'] as String? ?? 'native',
        ));
      }
    } catch (_) {}

    if (_osStatsAvailable) {
      try {
        final stats = await NativeNetworkChannel.getTrafficStats();
        if (stats.txBytes >= 0) _latestOsTxBytes = stats.txBytes;
        if (stats.rxBytes >= 0) _latestOsRxBytes = stats.rxBytes;
      } catch (_) {}
    }
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
