import 'dart:io';

import 'package:cfnb_app/core/latency/latency_prober.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 结果行（对应旧版 ResultsPanel 的表格行）。
class ResultRow {
  final String node; // ip:port#CC
  final String? speed; // "12.34 Mbps" 或 null
  final String? latency; // "50.00 ms" 或 null
  final double? quality; // 综合质量分 Q（0-1），无则 null
  ResultRow(this.node, [this.speed, this.latency, this.quality]);

  String get ipPort => node.split('#').first;
  String get country => nodeCountry(node);
}

/// 解析 ip.txt / addressesapi*.txt 内容为结果行。
/// 兼容两种格式：
///   - 带测速："1.2.3.4:443#US 12.34 Mbps 50.00 ms"
///   - 纯节点："1.2.3.4:443#US"
List<ResultRow> parseResultLines(String text) {
  final rows = <ResultRow>[];
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split(RegExp(r'\s+'));
    final node = parts.first;
    if (!node.contains(':')) continue;
    String? speed;
    String? latency;
    double? quality;
    if (parts.length > 1) {
      // 剩余片段中识别 "120.50 Mbps" / "30.10 ms"（值+单位）
      final tokens = parts.skip(1).toList();
      for (var i = 0; i < tokens.length; i++) {
        final p = tokens[i];
        if (p.contains('Mbps')) speed ??= (i > 0 ? '${tokens[i - 1]} $p' : p);
        if (p.contains('ms')) latency ??= (i > 0 ? '${tokens[i - 1]} $p' : p);
        if (p.startsWith('Q')) {
          final q = double.tryParse(p.substring(1));
          quality ??= q;
        }
      }
    }
    rows.add(ResultRow(node, speed, latency, quality));
  }
  return rows;
}

class ResultState {
  final List<ResultRow> rows;
  final String? sourceLabel;
  final String? currentFile;
  final String? rawText;
  ResultState({this.rows = const [], this.sourceLabel, this.currentFile, this.rawText});
  ResultState copyWith({
    List<ResultRow>? rows,
    String? sourceLabel,
    String? currentFile,
    String? rawText,
    bool clearFile = false,
  }) =>
      ResultState(
        rows: rows ?? this.rows,
        sourceLabel: sourceLabel ?? this.sourceLabel,
        currentFile: clearFile ? null : (currentFile ?? this.currentFile),
        rawText: clearFile ? null : (rawText ?? this.rawText),
      );
}

class ResultNotifier extends StateNotifier<ResultState> {
  ResultNotifier() : super(ResultState());

  void setRows(List<ResultRow> rows, [String? sourceLabel]) {
    state = state.copyWith(rows: rows, sourceLabel: sourceLabel);
  }

  /// 从文件加载（用于「刷新」与单步执行后）。
  /// 同时保存原始文本，供「查看文件内容」面板使用。
  Future<void> loadFile(String path) async {
    final f = File(path);
    if (!f.existsSync()) {
      state = state.copyWith(clearFile: true);
      return;
    }
    final text = await f.readAsString();
    state = state.copyWith(
      rows: parseResultLines(text),
      sourceLabel: path.split(RegExp(r'[\\/]')).last,
      currentFile: path,
      rawText: text,
    );
  }

  /// 仅加载某文件的原始内容（不解析为节点表），用于查看 work/ 中间产物。
  Future<void> loadRaw(String path) async {
    final f = File(path);
    if (!f.existsSync()) {
      state = state.copyWith(clearFile: true);
      return;
    }
    final text = await f.readAsString();
    state = state.copyWith(
      rows: parseResultLines(text),
      sourceLabel: path.split(RegExp(r'[\\/]')).last,
      currentFile: path,
      rawText: text,
    );
  }

  /// 从节点行列表加载（单步：获取数据源 / 可用性结果）。
  void loadLines(List<String> lines, [String? label]) {
    final rows = lines
        .where((l) => l.trim().isNotEmpty && !l.trim().startsWith('#'))
        .map((l) => ResultRow(l.trim()))
        .toList();
    state = state.copyWith(rows: rows, sourceLabel: label);
  }

  /// 从 "节点 -> 数值" 映射加载（单步：TCP 延迟 / 带宽测速结果）。
  void loadMap(Map<String, double> map, String label) {
    final rows = map.entries
        .map((e) => ResultRow(e.key, e.value.toStringAsFixed(2)))
        .toList();
    state = state.copyWith(rows: rows, sourceLabel: label);
  }

  Map<String, int> geoDistribution() {
    final map = <String, int>{};
    for (final r in state.rows) {
      final c = r.country.isEmpty ? '未知' : r.country;
      map[c] = (map[c] ?? 0) + 1;
    }
    return map;
  }

  double? bestSpeed() {
    double? best;
    for (final r in state.rows) {
      if (r.speed == null) continue;
      final v = double.tryParse(r.speed!.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (v != null && (best == null || v > best)) best = v;
    }
    return best;
  }

  double? lowestLatency() {
    double? low;
    for (final r in state.rows) {
      if (r.latency == null) continue;
      final v = double.tryParse(r.latency!.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (v != null && (low == null || v < low)) low = v;
    }
    return low;
  }
}

final resultProvider = StateNotifierProvider<ResultNotifier, ResultState>(
  (ref) => ResultNotifier(),
);
