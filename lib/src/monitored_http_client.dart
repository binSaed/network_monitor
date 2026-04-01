import 'dart:convert';

import 'package:http/http.dart' as http;

import 'network_monitor_service.dart';
import 'network_request_record.dart';

/// A wrapper around [http.Client] that records all requests to
/// [NetworkMonitorService].
///
/// ```dart
/// final client = MonitoredHttpClient(http.Client());
/// final response = await client.get(Uri.parse('https://example.com'));
/// ```
class MonitoredHttpClient extends http.BaseClient {
  final http.Client _inner;

  MonitoredHttpClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final service = NetworkMonitorService.instance;
    if (!service.isInitialized) return _inner.send(request);

    final stopwatch = Stopwatch()..start();
    final requestSize =
        _estimateRequestSize(request);

    try {
      final streamedResponse = await _inner.send(request);
      stopwatch.stop();

      // Buffer the response body so we can measure it and still return it.
      final bodyBytes = await streamedResponse.stream.toBytes();
      final responseSize =
          bodyBytes.length + _estimateHeadersSize(streamedResponse.headers);

      service.addRecord(NetworkRequestRecord(
        url: request.url.toString(),
        method: request.method,
        statusCode: streamedResponse.statusCode,
        requestSizeBytes: requestSize,
        responseSizeBytes: responseSize,
        timestamp: DateTime.now(),
        duration: stopwatch.elapsed,
        source: 'http',
      ));

      // Return a new StreamedResponse with the buffered bytes.
      return http.StreamedResponse(
        http.ByteStream.fromBytes(bodyBytes),
        streamedResponse.statusCode,
        contentLength: streamedResponse.contentLength,
        request: streamedResponse.request,
        headers: streamedResponse.headers,
        isRedirect: streamedResponse.isRedirect,
        reasonPhrase: streamedResponse.reasonPhrase,
      );
    } catch (e) {
      stopwatch.stop();

      service.addRecord(NetworkRequestRecord(
        url: request.url.toString(),
        method: request.method,
        statusCode: 0,
        requestSizeBytes: requestSize,
        responseSizeBytes: 0,
        timestamp: DateTime.now(),
        duration: stopwatch.elapsed,
        source: 'http',
      ));

      rethrow;
    }
  }

  int _estimateRequestSize(http.BaseRequest request) {
    var size = _estimateHeadersSize(request.headers);
    if (request is http.Request) {
      size += utf8.encode(request.body).length;
    } else if (request is http.MultipartRequest) {
      for (final field in request.fields.entries) {
        size += utf8.encode(field.key).length + utf8.encode(field.value).length;
      }
      for (final file in request.files) {
        size += file.length;
      }
    }
    return size;
  }

  int _estimateHeadersSize(Map<String, String> headers) {
    var size = 0;
    headers.forEach((key, value) {
      size += key.length + value.length + 4;
    });
    return size;
  }

  @override
  void close() {
    _inner.close();
  }
}
