import 'dart:async';

import 'package:flutter/material.dart';

import '../network_monitor_service.dart';
import '../network_request_record.dart';
import 'network_request_tile.dart';
import 'network_domain_group.dart';

enum _SortField { timestamp, size, duration }

enum _SourceFilter { all, dio, native }

enum _GroupMode { none, domain, path }

class NetworkMonitorPage extends StatefulWidget {
  final Duration refreshInterval;

  const NetworkMonitorPage({
    super.key,
    this.refreshInterval = const Duration(seconds: 2),
  });

  @override
  State<NetworkMonitorPage> createState() => _NetworkMonitorPageState();
}

class _NetworkMonitorPageState extends State<NetworkMonitorPage> {
  final _service = NetworkMonitorService.instance;
  Timer? _refreshTimer;

  _SortField _sortField = _SortField.timestamp;
  bool _sortAscending = false;
  _SourceFilter _sourceFilter = _SourceFilter.all;
  _GroupMode _groupMode = _GroupMode.none;

  @override
  void initState() {
    super.initState();
    _service.fetchNativeRecords().then((_) {
      if (mounted) setState(() {});
    });
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) async {
      await _service.fetchNativeRecords();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  List<NetworkRequestRecord> get _sourceFiltered {
    final records = _service.records;
    switch (_sourceFilter) {
      case _SourceFilter.all:
        return records;
      case _SourceFilter.dio:
        return records.where((r) => NetworkMonitorService.isDartSource(r.source)).toList();
      case _SourceFilter.native:
        return records.where((r) => !NetworkMonitorService.isDartSource(r.source)).toList();
    }
  }

  List<NetworkRequestRecord> get _filteredRecords {
    final records = List<NetworkRequestRecord>.from(_sourceFiltered);
    records.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case _SortField.timestamp:
          cmp = a.timestamp.compareTo(b.timestamp);
        case _SortField.size:
          cmp = a.totalBytes.compareTo(b.totalBytes);
        case _SortField.duration:
          cmp = a.duration.compareTo(b.duration);
      }
      return _sortAscending ? cmp : -cmp;
    });
    return records;
  }

  Map<String, List<NetworkRequestRecord>> get _grouped {
    final map = <String, List<NetworkRequestRecord>>{};
    for (final record in _filteredRecords) {
      final key = _groupMode == _GroupMode.domain
          ? record.domain
          : '${record.method} ${record.path.isEmpty ? record.url : record.path}';
      map.putIfAbsent(key, () => []).add(record);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xff1A1A2E) : Colors.white;
    final cardColor = isDark ? const Color(0xff16213E) : const Color(0xffF8F9FA);
    final borderColor = isDark ? const Color(0xff2A2A4A) : const Color(0xffE9ECEF);
    final textMain = isDark ? Colors.white : const Color(0xff212529);
    final textMuted = isDark ? const Color(0xff9CA3AF) : const Color(0xff6C757D);
    final accent = const Color(0xff0078FF);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: textMain, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Network Monitor',
          style: TextStyle(
            color: textMain,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline, color: textMuted, size: 22),
            onPressed: () {
              _service.clearRecords();
              setState(() {});
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSummary(cardColor, borderColor, textMain, textMuted, accent),
          _buildFilterBar(cardColor, borderColor, textMain, textMuted, accent),
          Expanded(
            child: _groupMode != _GroupMode.none
                ? _buildGroupedList(borderColor, textMain, textMuted, accent)
                : _buildFlatList(borderColor, textMain, textMuted, accent),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(
    Color cardColor,
    Color borderColor,
    Color textMain,
    Color textMuted,
    Color accent,
  ) {
    final fmt = NetworkMonitorService.formatBytes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        children: [
          Row(
            children: [
              _summaryCard('Total Sent', fmt(_service.totalTxBytes), Icons.arrow_upward,
                  Colors.orange, cardColor, borderColor, textMain, textMuted),
              const SizedBox(width: 8),
              _summaryCard('Total Received', fmt(_service.totalRxBytes), Icons.arrow_downward,
                  Colors.blue, cardColor, borderColor, textMain, textMuted),
              const SizedBox(width: 8),
              _summaryCard('Requests', '${_sourceFiltered.length}', Icons.http, accent,
                  cardColor, borderColor, textMain, textMuted),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _miniStat('Flutter (Dio/HTTP)',
                  '${fmt(_service.totalDioTxBytes)} / ${fmt(_service.totalDioRxBytes)}',
                  cardColor, textMain, textMuted),
              const SizedBox(width: 8),
              _miniStat('Native',
                  '${fmt(_service.totalNativeTxBytes)} / ${fmt(_service.totalNativeRxBytes)}',
                  cardColor, textMain, textMuted),
              if (_service.osStatsAvailable) ...[
                const SizedBox(width: 8),
                _miniStat('Untracked',
                    fmt(_service.untrackedTxBytes + _service.untrackedRxBytes),
                    cardColor, textMain, textMuted),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(
    String label,
    String value,
    IconData icon,
    Color iconColor,
    Color cardColor,
    Color borderColor,
    Color textMain,
    Color textMuted,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: textMain)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color cardColor, Color textMain, Color textMuted) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: cardColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 10, color: textMuted)),
            const SizedBox(height: 2),
            Text(value,
                style: TextStyle(fontWeight: FontWeight.w500, fontSize: 11, color: textMain),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(
    Color cardColor,
    Color borderColor,
    Color textMain,
    Color textMuted,
    Color accent,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              _sourceChip('All', _SourceFilter.all, accent, borderColor, textMuted),
              const SizedBox(width: 6),
              _sourceChip('Flutter', _SourceFilter.dio, accent, borderColor, textMuted),
              const SizedBox(width: 6),
              _sourceChip('Native', _SourceFilter.native, accent, borderColor, textMuted),
              const Spacer(),
              _groupChip('Domain', _GroupMode.domain, accent, borderColor, textMuted),
              const SizedBox(width: 4),
              _groupChip('URL', _GroupMode.path, accent, borderColor, textMuted),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Sort by:', style: TextStyle(fontSize: 11, color: textMuted)),
              const SizedBox(width: 6),
              _sortChip('Time', _SortField.timestamp, accent, textMuted),
              const SizedBox(width: 6),
              _sortChip('Size', _SortField.size, accent, textMuted),
              const SizedBox(width: 6),
              _sortChip('Duration', _SortField.duration, accent, textMuted),
            ],
          ),
          const SizedBox(height: 8),
          Divider(color: borderColor, height: 1),
        ],
      ),
    );
  }

  Widget _groupChip(
    String label,
    _GroupMode mode,
    Color accent,
    Color borderColor,
    Color textMuted,
  ) {
    final selected = _groupMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _groupMode = selected ? _GroupMode.none : mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? accent : borderColor),
        ),
        child: Text(label,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 11,
              color: selected ? accent : textMuted,
            )),
      ),
    );
  }

  Widget _sourceChip(
    String label,
    _SourceFilter filter,
    Color accent,
    Color borderColor,
    Color textMuted,
  ) {
    final selected = _sourceFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _sourceFilter = filter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? accent : borderColor),
        ),
        child: Text(label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: selected ? Colors.white : textMuted,
            )),
      ),
    );
  }

  Widget _sortChip(String label, _SortField field, Color accent, Color textMuted) {
    final selected = _sortField == field;
    return GestureDetector(
      onTap: () => setState(() {
        if (_sortField == field) {
          _sortAscending = !_sortAscending;
        } else {
          _sortField = field;
          _sortAscending = false;
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 11,
                  color: selected ? accent : textMuted,
                )),
            if (selected)
              Icon(
                _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: accent,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlatList(Color borderColor, Color textMain, Color textMuted, Color accent) {
    final records = _filteredRecords;
    if (records.isEmpty) {
      return Center(
        child: Text('No network requests recorded yet',
            style: TextStyle(fontSize: 14, color: textMuted)),
      );
    }
    return ListView.builder(
      itemCount: records.length,
      itemBuilder: (_, index) => NetworkRequestTile(
        record: records[index],
        borderColor: borderColor,
        textMain: textMain,
        textMuted: textMuted,
      ),
    );
  }

  Widget _buildGroupedList(Color borderColor, Color textMain, Color textMuted, Color accent) {
    final grouped = _grouped;
    if (grouped.isEmpty) {
      return Center(
        child: Text('No network requests recorded yet',
            style: TextStyle(fontSize: 14, color: textMuted)),
      );
    }
    final entries = grouped.entries.toList()
      ..sort((a, b) {
        final aTotal = a.value.fold(0, (sum, r) => sum + r.totalBytes);
        final bTotal = b.value.fold(0, (sum, r) => sum + r.totalBytes);
        return bTotal.compareTo(aTotal);
      });
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (_, index) {
        final entry = entries[index];
        return NetworkDomainGroup(
          domain: entry.key,
          records: entry.value,
          borderColor: borderColor,
          textMain: textMain,
          textMuted: textMuted,
          accent: accent,
        );
      },
    );
  }
}
