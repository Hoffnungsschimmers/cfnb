import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../widgets/common.dart';
import '../../app/providers.dart';
import '../subscriptions/subscriptions_state.dart';
import 'result_state.dart';
import '../../core/config/app_config.dart';
import 'package:path_provider/path_provider.dart';

class ResultsTab extends ConsumerStatefulWidget {
  const ResultsTab({super.key});
  @override
  ConsumerState<ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends ConsumerState<ResultsTab> {
  String? _selectedFile;
  bool _rawView = false;
  bool _pushing = false;

  // 候选输出文件（相对名 -> 解析后的绝对路径），用于存在性检查与下拉。
  List<String> _candidateNames = [];
  List<String> _candidatePaths = [];

  /// 输出文件现在写入文档目录，存在性检查必须解析到绝对路径。
  Future<void> _refreshCandidates(AppConfig? cfg) async {
    final names = <String>[
      cfg?.subOutputFile ?? 'addressesapi.txt',
      cfg?.subLatencyOutputFile ?? 'addressesapi_top.txt',
    ].where((p) => p.isNotEmpty).toSet().toList();
    final dir = (await getApplicationDocumentsDirectory()).path;
    final paths = names.map((n) => resolveOutputPath(n, dir)).toList();
    if (!mounted) return;
    setState(() {
      _candidateNames = names;
      _candidatePaths = paths;
    });
  }

  @override
  void initState() {
    super.initState();
    _refreshCandidates(ref.read(configProvider).value);
    ref.listenManual(configProvider, (_, next) {
      _refreshCandidates(next.value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final state = ref.watch(resultProvider);
    final cfgAsync = ref.watch(configProvider);

    // 仅保留实际存在的候选（按文档目录绝对路径判断）。
    final existing = <String>[];
    for (var i = 0; i < _candidateNames.length; i++) {
      if (File(_candidatePaths[i]).existsSync()) existing.add(_candidateNames[i]);
    }
    final candidates = existing;

    _selectedFile ??= state.currentFile ?? (candidates.isNotEmpty ? candidates.first : null);
    final effectiveSelected =
        (_selectedFile != null && candidates.contains(_selectedFile)) ? _selectedFile! : candidates.first;

    final rows = state.rows;
    final geo = <String, int>{};
    for (final r in rows) {
      final c = r.country.isEmpty ? '未知' : r.country;
      geo[c] = (geo[c] ?? 0) + 1;
    }

    final lowestLatency = _lowestLatency(rows);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final maxW = constraints.maxWidth > 1100 ? 1080.0 : constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('优选结果',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                )),
                      ),
                      if (state.sourceLabel != null)
                        pill(context, state.sourceLabel!, t.surfaceHover, t.textDim),
                      const SizedBox(width: 12),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.refresh),
                        tooltip: '刷新',
                        onPressed: () async {
                          final cfg = cfgAsync.value;
                          if (cfg != null) {
                            _selectedFile = cfg.subLatencyOutputFile;
                            _rawView = false;
                            setState(() {});
                            await ref.read(resultProvider.notifier).loadFile(cfg.subLatencyOutputFile);
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      _pushGithubButton(context, cfgAsync.value?.subLatencyOutputFile ?? 'addressesapi_top.txt'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 文件选择器 + 视图切换
                  if (candidates.isNotEmpty)
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: t.surface,
                            borderRadius: t.radius,
                            border: Border.all(color: t.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: effectiveSelected,
                              items: candidates
                                  .map((c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(c, style: const TextStyle(fontFamily: 'Consolas', fontSize: 13)),
                                      ))
                                  .toList(),
                              onChanged: (v) async {
                                if (v == null) return;
                                _selectedFile = v;
                                setState(() {});
                                await ref.read(resultProvider.notifier).loadRaw(v);
                              },
                            ),
                          ),
                        ),
                        ToggleButtons(
                          isSelected: [!_rawView, _rawView],
                          borderRadius: t.radius,
                          selectedColor: Colors.white,
                          fillColor: AppTheme.edgeOrange,
                          color: t.textDim,
                          onPressed: (i) => setState(() => _rawView = i == 1),
                          children: const [
                            Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text('解析视图')),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: Text('原始内容')),
                          ],
                        ),
                      ],
                    ),
                  const SizedBox(height: 16),
                  if (rows.isEmpty && !_rawView)
                    card(
                      context,
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_outlined, size: 48, color: t.textDim),
                          const SizedBox(height: 12),
                          Text('暂无结果',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: t.text)),
                          const SizedBox(height: 6),
                          Text('运行「单步执行」或「开始优选」后，结果会显示在这里。',
                              style: TextStyle(color: t.textDim)),
                        ],
                      ),
                    )
                  else if (_rawView)
                    card(
                      context,
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                        height: 420,
                        child: (state.rawText == null || state.currentFile != _selectedFile)
                            ? Center(child: Text('加载中…', style: TextStyle(color: t.textDim)))
                            : RawTextView(state.rawText!, copyTooltip: '复制文件内容'),
                      ),
                    )
                  else ...[
                    ResultStatsRow(rows: rows, geo: geo, lowestLatency: lowestLatency),
                    const SizedBox(height: 16),
                    if (geo.length > 1)
                      card(
                        context,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('国家 / 地区分布', style: TextStyle(color: t.textDim, fontSize: 12)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: geo.entries
                                  .map((e) => Chip(
                                        label: Text('${e.key}  ${e.value}'),
                                        backgroundColor: t.bg,
                                        side: BorderSide(color: t.border),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    ResultTable(rows: rows),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pushGithubButton(BuildContext context, String file) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.edgeOrange,
        side: BorderSide(color: AppTheme.edgeOrange),
      ),
      onPressed: _pushing
          ? null
          : () async {
              setState(() => _pushing = true);
              try {
                final (ok, code, msg) =
                    await ref.read(subProvider.notifier).pushFile(file);
                if (!mounted) return;
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (messenger != null) {
                  messenger.showSnackBar(SnackBar(
                    content: Text(msg),
                    backgroundColor:
                        ok ? Colors.green.shade700 : Colors.red.shade700,
                    duration: const Duration(seconds: 4),
                  ));
                }
              } finally {
                if (mounted) setState(() => _pushing = false);
              }
            },
      icon: _pushing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cloud_upload),
      label: Text(_pushing ? '推送中…' : '推送 GitHub'),
    );
  }

  double? _lowestLatency(List<ResultRow> rows) {
    double? low;
    for (final r in rows) {
      if (r.latency == null) continue;
      final v = double.tryParse(r.latency!.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (v != null && (low == null || v < low)) low = v;
    }
    return low;
  }
}

class ResultStatsRow extends StatelessWidget {
  const ResultStatsRow({
    super.key,
    required this.rows,
    required this.geo,
    required this.lowestLatency,
  });

  final List<ResultRow> rows;
  final Map<String, int> geo;
  final double? lowestLatency;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _stat(context, '节点数', '${rows.length}', Icons.storage),
        _stat(context, '来源数', '${geo.length}', Icons.public),
        _stat(context, '最低延迟',
            lowestLatency != null ? '${lowestLatency!.toStringAsFixed(0)} ms' : '—', Icons.timeline),
      ],
    );
  }

  Widget _stat(BuildContext context, String title, String value, IconData icon) {
    final t = AppThemeExt.of(context);
    return SizedBox(
      width: 200,
      child: card(
        context,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.edgeOrange, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 11, color: t.textDim)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ResultTable extends StatelessWidget {
  const ResultTable({super.key, required this.rows});

  final List<ResultRow> rows;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    return card(
      context,
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 520),
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(4),
              1: FlexColumnWidth(2),
              2: FlexColumnWidth(2),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: t.surfaceHover),
                children: [
                  _th(context, '节点'),
                  _th(context, '延迟'),
                  _th(context, '国家'),
                ],
              ),
              for (final r in rows)
                TableRow(
                  children: [
                    _td(context, r.node),
                    _td(context, r.latency ?? '—'),
                    _td(context, r.country.isEmpty ? '—' : r.country),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _th(BuildContext context, String s) {
    final t = AppThemeExt.of(context);
    return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(s, style: TextStyle(fontWeight: FontWeight.bold, color: t.textDim)));
  }

  Widget _td(BuildContext context, String s) {
    final t = AppThemeExt.of(context);
    return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(s, style: TextStyle(color: t.text, fontFamily: 'Consolas')));
  }
}
