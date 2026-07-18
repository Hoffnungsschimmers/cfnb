p = "lib/features/results/result_state.dart"
s = open(p, encoding="utf-8").read()

anchor = """  /// 从文件加载（用于「刷新」与单步执行后）。
  Future<void> loadFile(String path) async {
    final f = File(path);
    if (!f.existsSync()) return;
    final text = await f.readAsString();
    state = state.copyWith(rows: parseResultLines(text), sourceLabel: path.split(RegExp(r'[\\\\/]')).last);
  }
"""
assert anchor in s, "loadFile anchor not found"

extra = """
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
        .map((e) => ResultRow(e.key, valueText: '${e.value.toStringAsFixed(2)}'))
        .toList();
    state = state.copyWith(rows: rows, sourceLabel: label);
  }
"""

s = s.replace(anchor, anchor + extra)
open(p, "w", encoding="utf-8").write(s)
print("result_state loadLines/loadMap added")
