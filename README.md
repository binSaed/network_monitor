# Network Monitor

A Flutter plugin for monitoring and analyzing HTTP network traffic across Dart (`dio`, `http`) and native platform layers. Includes a built-in diagnostic UI to visualize, filter, and analyze network requests in real-time.

## Features

- **Dart HTTP tracking** — Intercepts traffic from both the `dio` and `http` packages via dedicated wrappers
- **Native tracking** — Intercepts native HTTP clients (HttpURLConnection on Android, URLSession on iOS)
- **System-level stats** — Detects untracked traffic by comparing OS-level byte counters against recorded requests (Android)
- **Built-in UI** — Full-featured monitor page with filtering, sorting, grouping, and expandable request details
- **Request metrics** — Captures URL, method, status code, request/response sizes, duration, and timestamps
- **Dark/Light theme** — Adaptive UI with color-coded HTTP methods and status codes

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  network_monitor:
    git:
      url: https://github.com/binSaed/network_monitor.git
```

## Usage

### 1. Initialize the service

```dart
import 'package:network_monitor/network_monitor.dart';

await NetworkMonitorService.instance.init();
```

### 2. Add the Dio interceptor

```dart
final dio = Dio();
dio.interceptors.add(NetworkUsageInterceptor());
```

### 3. Wrap your HTTP client

```dart
import 'package:http/http.dart' as http;

final client = MonitoredHttpClient(http.Client());
final response = await client.get(Uri.parse('https://example.com'));
```

### 4. Open the monitor UI

```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const NetworkMonitorPage()),
);
```

Native HTTP traffic (Android `HttpURLConnection`, iOS `URLSession`) is automatically intercepted once the plugin is loaded.

## Monitor UI

The monitor page provides:

- **Summary cards** — Total sent/received bytes and request count
- **Source filters** — View All, Flutter-only, or Native-only requests
- **Grouping** — Group requests by domain or URL path
- **Sorting** — Sort by timestamp, size, or duration
- **Request details** — Tap any request to expand full metadata (URL, status, sizes, duration, source)
- **Copy URL** — Long-press or tap the copy icon on any request

## Platform Support

| Platform | Native Interception | Traffic Stats |
|----------|---------------------|---------------|
| Android  | `ResponseCache` hook | `TrafficStats` API |
| iOS      | `URLProtocol` + swizzling | Not available |

### Requirements

- Flutter SDK `>=3.11.4`
- Android `minSdk: 24`, `compileSdk: 36`
- iOS `>=13.0`

## Architecture

```
lib/
├── network_monitor.dart              # Public API exports
└── src/
    ├── network_monitor_service.dart   # Core service (singleton, record management)
    ├── network_request_record.dart    # Data model
    ├── network_usage_interceptor.dart # Dio interceptor
    ├── monitored_http_client.dart     # http package wrapper
    ├── native_channel.dart            # Platform channel bridge
    └── ui/
        ├── network_monitor_page.dart  # Main monitor screen
        ├── network_request_tile.dart  # Request list item
        └── network_domain_group.dart  # Domain grouping widget
```

## Configuration

| Setting | Default | How to change |
|---------|---------|---------------|
| Max Dart records | 1,000 | `NetworkMonitorService.instance.init(maxRecords: 2000)` |
| Max native records | 500 | `NetworkMonitorService.instance.init(maxNativeRecords: 1000)` |
| Native poll interval | 2 seconds | `NetworkMonitorPage(refreshInterval: Duration(seconds: 5))` |

## License

See [LICENSE](LICENSE) for details.
