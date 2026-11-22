import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/diagnostics_log.dart';
import '../data/app_database.dart';
import '../data/crash_test.dart';
import '../data/diagnostics_upload.dart';
import '../data/net.dart';
import '../player/resource_counters.dart';
import '../theme.dart';
import '../widgets/app_bar_action.dart';
import 'crash_test_section.dart';
import 'send_diagnostics_screen.dart';

class DiagnosticsScreen extends StatelessWidget {
  final AppDatabase? database;
  final String? sourceId;
  final Future<void> Function()? onReingest;

  const DiagnosticsScreen({
    super.key,
    this.database,
    this.sourceId,
    this.onReingest,
  });

  @override
  Widget build(BuildContext context) {
    final log = DiagnosticsLog.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('诊断信息'),
        // `AppBarAction`, not bare `IconButton`s (CLAUDE.md): on the wide
        // layout — which is every television — these name themselves, because
        // a remote cannot hover a tooltip and "a clipboard" and "a bin" are
        // not obvious choices to make about your own diagnostics.
        actions: [
          AppBarAction(
            // Send is the reason most people reach this screen, but it is
            // *not* the autofocus target: it leads to a route whose own
            // default focus is Cancel, and landing a D-pad on "send my log"
            // is the wrong first impression of a diagnostics screen.
            label: 'Send',
            tooltip: '向开发者发送诊断信息',
            icon: Icons.send_outlined,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                // The snapshot is taken HERE, at the moment the user asks to
                // send, and carried into the route — so the log shown beside
                // the consent text is byte-for-byte the log that goes.
                builder: (_) =>
                    SendDiagnosticsScreen(snapshot: diagnosticsSnapshot()),
              ),
            ),
          ),
          AppBarAction(
            autofocus: true,
            label: 'Copy',
            tooltip: '复制完整日志到剪贴板',
            icon: Icons.copy_outlined,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: log.asText()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('诊断信息已复制')),
              );
            },
          ),
          AppBarAction(
            label: 'Clear',
            tooltip: '清除此设备上的日志',
            icon: Icons.delete_outline,
            onPressed: log.clear,
          ),
          const SizedBox(width: 4),
        ],
      ),
      // Edge-to-edge (targetSdk 35+): keep the log list clear of the system bar,
      // which sits on the side in landscape.
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (kDebugMode) const _ResourceCountersSection(),
            // Only in the hand-dispatched crash-test build. `kCrashTest` is a
            // compile-time `const false` everywhere else, so this branch and
            // everything it reaches are tree-shaken out of a shipped app.
            if (kCrashTest) const CrashTestSection(),
            if (database != null && sourceId != null)
              _CacheStatsSection(
                database: database!,
                sourceId: sourceId!,
                onReingest: onReingest,
              ),
            Expanded(
              child: AnimatedBuilder(
                animation: log,
                builder: (context, _) {
                  final entries = log.entries.reversed.toList();
                  if (entries.isEmpty) {
                    return const Center(
                      child: Text(
                        '暂无诊断信息',
                        style: TextStyle(color: AppColors.textLo),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: SelectableText(
                          '${_time(entry.time)}  ${redactText(entry.scope)}\n'
                          '${redactText(entry.message)}',
                          style: const TextStyle(
                            color: AppColors.textLo,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';
}

class _CacheStatsSection extends StatefulWidget {
  final AppDatabase database;
  final String sourceId;
  final Future<void> Function()? onReingest;

  const _CacheStatsSection({
    required this.database,
    required this.sourceId,
    this.onReingest,
  });

  @override
  State<_CacheStatsSection> createState() => _CacheStatsSectionState();
}

class _CacheStatsSectionState extends State<_CacheStatsSection> {
  late Future<CacheStats> _future = widget.database.cacheStats(widget.sourceId);

  void _refresh() {
    setState(() => _future = widget.database.cacheStats(widget.sourceId));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CacheStats>(
    future: _future,
    builder: (context, snapshot) {
      final stats = snapshot.data;
      if (stats == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(AppRadius.tile),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Cache  ${stats.channels} channels · '
                    '${stats.programmes} programmes · '
                    '${stats.mediaItems} media\n'
                    'Last refresh: ${_format(stats.lastChannelRefresh)}  '
                    'EPG: ${_format(stats.lastEpgRefresh)}',
                    style: const TextStyle(
                      color: AppColors.textLo,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '刷新缓存统计',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _refresh,
                ),
                if (widget.onReingest != null)
                  IconButton(
                    tooltip: '重新导入来源缓存',
                    icon: const Icon(Icons.sync, size: 20),
                    onPressed: () async {
                      await widget.onReingest!();
                      if (mounted) _refresh();
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  String _format(DateTime? value) =>
      value == null ? 'never' : '${value.toLocal()}'.split('.').first;
}

/// Debug-only tile showing the live [ResourceCounters.snapshot] — Dart-side
/// player/timer/handler counts plus, on Android/Windows, the native engine
/// counters — with a manual refresh affordance. Not shown in release builds
/// (see [kDebugMode] in [DiagnosticsScreen.build]).
class _ResourceCountersSection extends StatefulWidget {
  const _ResourceCountersSection();

  @override
  State<_ResourceCountersSection> createState() =>
      _ResourceCountersSectionState();
}

class _ResourceCountersSectionState extends State<_ResourceCountersSection> {
  late Future<Map<String, int>> _future = ResourceCounters.snapshot();

  void _refresh() {
    setState(() => _future = ResourceCounters.snapshot());
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(AppRadius.tile),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '资源计数器（调试）',
                    style: TextStyle(
                      color: AppColors.textHi,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '刷新计数器',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _refresh,
                  ),
                ],
              ),
              FutureBuilder<Map<String, int>>(
                future: _future,
                builder: (context, snapshot) {
                  final counters = snapshot.data;
                  if (counters == null) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '正在加载…',
                        style: TextStyle(color: AppColors.textLo, fontSize: 12),
                      ),
                    );
                  }
                  if (counters.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        '没有可用的计数信息',
                        style: TextStyle(color: AppColors.textLo, fontSize: 12),
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 4,
                      children: [
                        for (final entry in counters.entries)
                          Text(
                            '${entry.key}: ${entry.value}',
                            style: const TextStyle(
                              color: AppColors.textLo,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
