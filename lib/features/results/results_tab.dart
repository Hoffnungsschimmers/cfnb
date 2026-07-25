import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/latency/latency_prober.dart';
import '../../core/net/ip.dart';
import '../widgets/common.dart';
import '../../app/providers.dart';
import '../subscriptions/subscriptions_state.dart';
import 'result_state.dart';
import '../../core/config/app_config.dart';
import 'package:path_provider/path_provider.dart';

// ═══════════════════════════════════════════════════════
// 国旗 emoji 辅助
// ═══════════════════════════════════════════════════════

/// 国家码/中文名 → 国旗 emoji（Regional Indicator Symbol 对）。
/// 例：'HK' → 🇭🇰，'US' → 🇺🇸，'香港' → 🇭🇰。非 ASCII 或空返回空串。
String countryCodeToFlag(String input) {
  // 先尝试直接当国家码用，否则通过 normalizeCountryCode 反查
  String cc = input;
  if (input.length != 2 || input.codeUnitAt(0) > 127) {
    cc = normalizeCountryCode(input);
  }
  if (cc.length != 2) return '';
  final a = cc.codeUnitAt(0);
  final b = cc.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return '';
  return String.fromCharCode(0x1F1E6 + a - 65) + String.fromCharCode(0x1F1E6 + b - 65);
}

// ═══════════════════════════════════════════════════════
// ResultsTab
// ═══════════════════════════════════════════════════════

class ResultsTab extends ConsumerStatefulWidget {
  const ResultsTab({super.key});
  @override
  ConsumerState<ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends ConsumerState<ResultsTab> {
  String? _selectedFile;
  bool _rawView = false;
  bool _pushing = false;
  bool _editMode = false;
  final _addNodeCtrl = TextEditingController();

  // 排序状态
  int _sortCol = 1; // 默认按延迟列排序
  bool _sortAsc = true;

  // 缓存存在性检查结果，避免在 build() 中做同步 I/O。
  List<String> _existingCandidates = [];

  /// 输出文件现在写入文档目录，存在性检查必须解析到绝对路径。
  Future<void> _refreshCandidates(AppConfig? cfg) async {
    final names = <String>[
      cfg?.subOutputFile ?? 'addressesapi.txt',
      cfg?.subLatencyOutputFile ?? 'addressesapi_top.txt',
    ].where((p) => p.isNotEmpty).toSet().toList();
    final dir = (await getApplicationDocumentsDirectory()).path;
    final paths = names.map((n) => resolveOutputPath(n, dir)).toList();
    // 异步检查存在性，缓存结果
    final existing = <String>[];
    for (var i = 0; i < names.length; i++) {
      if (File(paths[i]).existsSync()) existing.add(names[i]);
    }
    if (!mounted) return;
    setState(() {
      _existingCandidates = existing;
    });
  }

  @override
  void dispose() {
    _addNodeCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _refreshCandidates(ref.read(configProvider).value);
    ref.listenManual(configProvider, (_, next) {
      _refreshCandidates(next.value);
    });
  }

  /// 国家分布统计（UI 层计算，避免 ref.read notifier）。
  static Map<String, int> _geoDistribution(List<ResultRow> rows) {
    final map = <String, int>{};
    for (final r in rows) {
      final c = r.country.isEmpty ? '未知' : r.country;
      map[c] = (map[c] ?? 0) + 1;
    }
    return map;
  }

  /// 最低延迟（UI 层计算）。
  static double? _lowestLatency(List<ResultRow> rows) {
    double? low;
    for (final r in rows) {
      if (r.latency == null) continue;
      final v = double.tryParse(r.latency!.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (v != null && (low == null || v < low)) low = v;
    }
    return low;
  }

  /// 对 rows 排序（UI 层，不污染 state）。
  List<ResultRow> _sortRows(List<ResultRow> rows) {
    final sorted = [...rows];
    sorted.sort((a, b) {
      int cmp;
      switch (_sortCol) {
        case 0: // 节点
          cmp = a.ipPort.compareTo(b.ipPort);
          break;
        case 1: // 延迟
          final la = _parseLatency(a.latency);
          final lb = _parseLatency(b.latency);
          if (la == null && lb == null) return 0;
          if (la == null) return 1; // null 沉底
          if (lb == null) return -1;
          cmp = la.compareTo(lb);
          break;
        case 2: // 国家
          cmp = a.country.compareTo(b.country);
          break;
        case 3: // 来源
          cmp = a.source.compareTo(b.source);
          break;
        default:
          cmp = 0;
      }
      return _sortAsc ? cmp : -cmp;
    });
    return sorted;
  }

  /// 从 "50.00 ms" 或 "50.00ms" 提取数值。
  static double? _parseLatency(String? s) {
    if (s == null) return null;
    return double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final state = ref.watch(resultProvider);
    final cfgAsync = ref.watch(configProvider);

    final candidates = _existingCandidates;

    _selectedFile ??= state.currentFile ?? (candidates.isNotEmpty ? candidates.first : null);
    final effectiveSelected =
        (_selectedFile != null && candidates.contains(_selectedFile))
            ? _selectedFile!
            : (candidates.isNotEmpty ? candidates.first : null);

    final rows = state.rows;
    final sortedRows = _sortRows(rows);
    // 从已 watch 的 state 直接计算，避免 ref.read
    final geo = _geoDistribution(rows);
    final lowestLatency = _lowestLatency(rows);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final maxW = constraints.maxWidth > 1100 ? 1080.0 : constraints.maxWidth;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Text('优选结果',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              )),
                      if (state.sourceLabel != null)
                        pill(context, state.sourceLabel!, t.surfaceHover),
                      if (state.generatedAt != null)
                        pill(context, '⏱ ${state.generatedAt}', t.surfaceHover),
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
                      IconButton.filledTonal(
                        icon: Icon(_editMode ? Icons.edit_off : Icons.edit),
                        tooltip: _editMode ? '退出编辑' : '编辑节点',
                        onPressed: () => setState(() => _editMode = !_editMode),
                      ),
                      _pushGithubButton(context, cfgAsync.value?.subLatencyOutputFile ?? 'addressesapi_top.txt'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 文件选择器（SegmentedButton）+ 视图切换
                  if (candidates.isNotEmpty)
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 500),
                          child: SegmentedButton<String>(
                            selected: {effectiveSelected ?? candidates.first},
                            onSelectionChanged: (s) async {
                              final v = s.first;
                              _selectedFile = v;
                              setState(() {});
                              await ref.read(resultProvider.notifier).loadFile(v);
                            },
                            segments: candidates
                                .map((c) => ButtonSegment(
                                      value: c,
                                      label: Text(c, style: const TextStyle(fontFamily: 'AppMono', fontSize: 12)),
                                    ))
                                .toList(),
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
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 32),
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: t.radius,
                        border: Border.all(color: t.border, width: 1),
                        // 虚线感：用两层圆角边框模拟
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: t.bg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: t.border.withValues(alpha: 0.5),
                            width: 1.5,
                            // Flutter 不支持原生虚线边框，用淡色双层圆角模拟插画感
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: AppTheme.edgeOrange.withValues(alpha: 0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.inbox_outlined, size: 32, color: AppTheme.edgeOrange.withValues(alpha: 0.6)),
                            ),
                            const SizedBox(height: 16),
                            Text('暂无结果',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: t.text)),
                            const SizedBox(height: 8),
                            Text('运行「订阅IP」和「延迟优选」后，结果会显示在这里。',
                                style: TextStyle(color: t.textDim, fontSize: 13)),
                          ],
                        ),
                      ),
                    )
                  else if (_rawView)
                    card(
                      context,
                      padding: const EdgeInsets.all(8),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.5,
                          minHeight: 200,
                        ),
                        child: (state.rawText == null || state.currentFile != _selectedFile)
                            ? Center(child: Text('加载中…', style: TextStyle(color: t.textDim)))
                            : RawTextView(state.rawText!, copyTooltip: '复制文件内容'),
                      ),
                    )
                  else ...[
                    ResultStatsRow(rows: rows, geo: geo, lowestLatency: lowestLatency),
                    const SizedBox(height: 16),
                    if (geo.length > 1) ...[
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
                                        label: Text('${countryCodeToFlag(e.key)} ${countryCodeToName(e.key)}  ${e.value}'),
                                        backgroundColor: t.bg,
                                        side: BorderSide(color: t.border),
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    ResultTable(
                      rows: sortedRows,
                      editMode: _editMode,
                      sortCol: _sortCol,
                      sortAsc: _sortAsc,
                      onSort: (col) {
                        setState(() {
                          if (_sortCol == col) {
                            _sortAsc = !_sortAsc;
                          } else {
                            _sortCol = col;
                            _sortAsc = true;
                          }
                        });
                      },
                      onDelete: (i) async {
                        // 排序后索引映射回原始 rows
                        final originalIdx = rows.indexOf(sortedRows[i]);
                        if (originalIdx >= 0) {
                          ref.read(resultProvider.notifier).removeRow(originalIdx);
                          await ref.read(resultProvider.notifier).saveToFile();
                        }
                      },
                    ),
                    if (_editMode) ...[
                      const SizedBox(height: 12),
                      card(
                        context,
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _addNodeCtrl,
                                style: const TextStyle(fontFamily: 'AppMono', fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'ip:port#CC source（如 1.2.3.4:443#US mia）',
                                  hintStyle: TextStyle(color: t.textDim, fontSize: 12),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  border: OutlineInputBorder(borderRadius: t.radius),
                                ),
                                onSubmitted: (_) => _addNode(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              icon: const Icon(Icons.add),
                              tooltip: '添加节点',
                              onPressed: _addNode,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _addNode() {
    final text = _addNodeCtrl.text.trim();
    if (text.isEmpty) return;
    ref.read(resultProvider.notifier).addRow(text);
    _addNodeCtrl.clear();
    ref.read(resultProvider.notifier).saveToFile();
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
                // 使用应用内 toast 替代 SnackBar
                AppToast.show(context, msg, success: ok);
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
}

// ═══════════════════════════════════════════════════════
// 统计区（count-up 动画）
// ═══════════════════════════════════════════════════════

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
        _stat(context, '节点数', rows.length.toDouble(), Icons.storage, decimals: 0),
        _stat(context, '国家/地区', geo.length.toDouble(), Icons.public, decimals: 0),
        _stat(context, '最低延迟', lowestLatency ?? 0, Icons.timeline, decimals: 0, suffix: ' ms'),
      ],
    );
  }

  Widget _stat(BuildContext context, String title, num value, IconData icon, {int decimals = 0, String? suffix}) {
    final t = AppThemeExt.of(context);
    return SizedBox(
      width: 180,
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
                  CountUpText(
                    value,
                    decimals: decimals,
                    suffix: suffix,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════
// 结果表格（排序 + 行内延迟条形图）
// ═══════════════════════════════════════════════════════

class ResultTable extends StatelessWidget {
  const ResultTable({
    super.key,
    required this.rows,
    this.editMode = false,
    this.onDelete,
    this.sortCol = 1,
    this.sortAsc = true,
    this.onSort,
  });

  final List<ResultRow> rows;
  final bool editMode;
  final void Function(int index)? onDelete;
  final int sortCol;
  final bool sortAsc;
  final void Function(int col)? onSort;

  @override
  Widget build(BuildContext context) {
    double maxLatency = 0;
    for (final r in rows) {
      final v = _parseLatency(r.latency);
      if (v != null && v > maxLatency) maxLatency = v;
    }

    // 列宽比例
    final colWidths = editMode
        ? [FlexColumnWidth(4), FlexColumnWidth(2), FlexColumnWidth(1.5), FlexColumnWidth(2), IntrinsicColumnWidth()]
        : [FlexColumnWidth(4), FlexColumnWidth(2), FlexColumnWidth(1.5), FlexColumnWidth(2)];

    return card(
      context,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // 列头（固定，不滚动）
          _headerRow(context, colWidths),
          // 数据行（虚拟化 ListView.builder）
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
            child: ListView.builder(
              itemCount: rows.length,
              itemExtent: 56, // 固定行高，提升性能
              itemBuilder: (context, i) {
                final row = rows[i];
                return _dataRow(context, i, row, maxLatency, colWidths);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 列头行
  Widget _headerRow(BuildContext context, List<TableColumnWidth> colWidths) {
    final t = AppThemeExt.of(context);
    return Table(
      columnWidths: {for (var i = 0; i < colWidths.length; i++) i: colWidths[i]},
      children: [
        TableRow(
          decoration: BoxDecoration(color: t.surfaceHover),
          children: [
            _sortHeader(context, '节点', 0),
            _sortHeader(context, '延迟', 1),
            _sortHeader(context, '国家', 2),
            _sortHeader(context, '来源', 3),
            if (editMode) _th(context, ''),
          ],
        ),
      ],
    );
  }

  /// 数据行
  Widget _dataRow(BuildContext context, int index, ResultRow row, double maxLatency, List<TableColumnWidth> colWidths) {
    final t = AppThemeExt.of(context);
    return Container(
      color: index.isOdd ? t.surfaceHover.withValues(alpha: 0.3) : null,
      child: Table(
        columnWidths: {for (var i = 0; i < colWidths.length; i++) i: colWidths[i]},
        children: [
          TableRow(children: [
            _nodeCell(context, row.ipPort),
            _latencyCell(context, row.latency, maxLatency),
            _countryCell(context, row.country, row.node),
            _td(context, row.source.isEmpty ? '—' : row.source),
            if (editMode)
              Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                  tooltip: '删除',
                  onPressed: () => onDelete?.call(index),
                ),
              ),
          ]),
        ],
      ),
    );
  }

  static double? _parseLatency(String? s) {
    if (s == null) return null;
    return double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), ''));
  }

  /// 可排序列头：点击切换排序，显示三角指示。
  Widget _sortHeader(BuildContext context, String label, int col) {
    final t = AppThemeExt.of(context);
    final isActive = sortCol == col;
    return InkWell(
      onTap: () => onSort?.call(col),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? t.text : t.textDim)),
            if (isActive)
              AnimatedRotation(
                turns: sortAsc ? 0 : 0.5,
                duration: Motion.durFast,
                child: Icon(Icons.arrow_drop_up, size: 18, color: AppTheme.edgeOrange),
              ),
          ],
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
        child: Text(s, style: TextStyle(color: t.text, fontFamily: 'AppMono')));
  }

  /// 节点列：IP/域名 用正文色，端口用淡色，长域名截断。
  Widget _nodeCell(BuildContext context, String ipPort) {
    final t = AppThemeExt.of(context);
    final lastColon = ipPort.lastIndexOf(':');
    final rawHost = lastColon > 0 ? ipPort.substring(0, lastColon) : ipPort;
    final port = lastColon > 0 ? ipPort.substring(lastColon) : '';
    final host = rawHost.length > 30
        ? '${rawHost.substring(0, 15)}...${rawHost.substring(rawHost.length - 10)}'
        : rawHost;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: RichText(
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        text: TextSpan(
          style: TextStyle(color: t.text, fontFamily: 'AppMono', fontSize: 14),
          children: [
            TextSpan(text: host),
            if (port.isNotEmpty)
              TextSpan(text: port, style: TextStyle(color: t.textDim)),
          ],
        ),
      ),
    );
  }

  /// 延迟列：数值 + 行内条形图。
  Widget _latencyCell(BuildContext context, String? latency, double maxLatency) {
    final t = AppThemeExt.of(context);
    final value = _parseLatency(latency);
    final display = latency ?? '—';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(display, style: TextStyle(color: t.text, fontFamily: 'AppMono', fontSize: 13)),
          if (value != null && maxLatency > 0) ...[
            const SizedBox(height: 4),
            _LatencyBar(value: value, maxLatency: maxLatency),
          ],
        ],
      ),
    );
  }

  /// 国家列：国旗 emoji + 国名。
  Widget _countryCell(BuildContext context, String countryName, String node) {
    final t = AppThemeExt.of(context);
    final cc = nodeCountry(node);
    final flag = countryCodeToFlag(cc);
    final display = countryName.isEmpty ? '—' : '$flag $countryName';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(display, style: TextStyle(color: t.text, fontFamily: 'AppMono', fontSize: 13)),
    );
  }
}

// ═══════════════════════════════════════════════════════
// 行内延迟条形图（CustomPainter）
// ═══════════════════════════════════════════════════════

class _LatencyBar extends StatelessWidget {
  final double value;
  final double maxLatency;
  const _LatencyBar({required this.value, required this.maxLatency});

  @override
  Widget build(BuildContext context) {
    final t = AppThemeExt.of(context);
    final ratio = (value / maxLatency).clamp(0.0, 1.0);
    final color = t.latencyTierColor(value);
    return CustomPaint(
      size: Size(double.infinity, 4),
      painter: _LatencyBarPainter(ratio: ratio, color: color, bgColor: t.border),
    );
  }
}

class _LatencyBarPainter extends CustomPainter {
  final double ratio;
  final Color color;
  final Color bgColor;
  _LatencyBarPainter({required this.ratio, required this.color, required this.bgColor});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromLTRBR(0, 0, size.width, size.height, const Radius.circular(2));
    // 背景条
    canvas.drawRRect(rrect, Paint()..color = bgColor);
    // 前景条
    final fgWidth = size.width * ratio;
    if (fgWidth > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, 0, fgWidth, size.height, const Radius.circular(2)),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_LatencyBarPainter old) =>
      old.ratio != ratio || old.color != color;
}
